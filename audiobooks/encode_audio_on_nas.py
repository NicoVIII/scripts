#!/usr/bin/env python3
"""
Batch convert .mka files on a Samba share to .m4a with subfolder-specific bitrates.
Requires: ffmpeg (via Docker), smbclient or cifs-utils, mka_to_aac.py in the same directory.
"""

import os
import sys
import subprocess
import tempfile
import shutil
from pathlib import Path
from getpass import getpass
from typing import Optional, Tuple, List
import logging

# ============================================================================
# CONFIGURATION - ADJUST THESE VALUES
# ============================================================================

# Samba server address
SMB_SERVER = "192.168.2.8"

# Optional SMB domain/workgroup. Leave empty if not needed.
SMB_DOMAIN = ""

# Try these SMB protocol versions in order until mount succeeds.
SMB_VERSION_CANDIDATES = ["3.1.1", "3.0", "2.1", "2.0", "1.0"]

# Try these security modes for authentication.
SMB_SECURITY_CANDIDATES = ["ntlmssp", "ntlmv2", "ntlm"]

# Share configuration.
# Each tuple is: (share_name, subfolders, bitrate)
# Use an empty subfolder "" to scan the full share recursively.
SHARE_CONFIGS: List[Tuple[str, List[str], str]] = [
    ("books", [""], "48k"),
    ("audiobooks", ["Hörspiele"], "64k"),
]

# ============================================================================
# LOGGING SETUP
# ============================================================================
logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s - %(levelname)s - %(message)s"
)
logger = logging.getLogger(__name__)

# ============================================================================
# HELPER FUNCTIONS
# ============================================================================
def mount_samba_share(server: str, share_name: str, credentials: Tuple[str, str]) -> str:
    """
    Mount Samba share using credentials. Returns mount point path.
    Requires: cifs-utils (mount.cifs)
    """
    username, password = credentials
    mount_point = tempfile.mkdtemp(prefix="samba_mount_")
    unc_path = f"//{server}/{share_name}"
    last_error = "Unknown error"

    # Use a temporary credentials file so password does not appear in process args.
    with tempfile.NamedTemporaryFile("w", prefix="smb_creds_", delete=False) as cred_file:
        cred_file.write(f"username={username}\n")
        cred_file.write(f"password={password}\n")
        if SMB_DOMAIN:
            cred_file.write(f"domain={SMB_DOMAIN}\n")
        cred_file_path = cred_file.name

    try:
        os.chmod(cred_file_path, 0o600)
        for smb_version in SMB_VERSION_CANDIDATES:
            for smb_sec in SMB_SECURITY_CANDIDATES:
                options = (
                    f"credentials={cred_file_path},"
                    f"uid={os.getuid()},gid={os.getgid()},"
                    f"iocharset=utf8,vers={smb_version},sec={smb_sec}"
                )
                mount_cmd = ["sudo", "mount.cifs", unc_path, mount_point, "-o", options]

                try:
                    subprocess.run(mount_cmd, check=True, capture_output=True)
                    logger.info(
                        f"Mounted Samba share at {mount_point} "
                        f"(SMB {smb_version}, sec={smb_sec})"
                    )
                    return mount_point
                except subprocess.CalledProcessError as e:
                    last_error = e.stderr.decode(errors="replace").strip()
                    logger.warning(
                        f"Mount failed with SMB {smb_version}, sec={smb_sec} "
                        f"for {unc_path}: {last_error}"
                    )

        raise RuntimeError(
            "Failed to mount Samba share after trying SMB versions "
            f"{', '.join(SMB_VERSION_CANDIDATES)} and sec modes "
            f"{', '.join(SMB_SECURITY_CANDIDATES)} for {unc_path}. "
            f"Last error: {last_error}"
        )
    finally:
        try:
            os.remove(cred_file_path)
        except OSError:
            pass

def unmount_samba_share(mount_point: str) -> None:
    """Unmount Samba share."""
    try:
        subprocess.run(["sudo", "umount", mount_point], check=True, capture_output=True)
        logger.info(f"Unmounted Samba share from {mount_point}")
        shutil.rmtree(mount_point, ignore_errors=True)
    except subprocess.CalledProcessError as e:
        logger.warning(f"Failed to unmount {mount_point}: {e.stderr.decode()}")

def find_mka_files(mount_point: str, subfolder: str) -> List[Tuple[str, str]]:
    """
    Recursively find all .mka files in the given subfolder on the mounted share.
    Returns list of (full_path, relative_path_from_subfolder) tuples.
    """
    subfolder_path = os.path.join(mount_point, subfolder)
    mka_files: List[Tuple[str, str]] = []
    
    if not os.path.isdir(subfolder_path):
        logger.warning(f"Subfolder does not exist: {subfolder_path}")
        return mka_files
    
    for root, _, files in os.walk(subfolder_path):
        # Only process files if the immediate parent directory is named "source"
        if os.path.basename(root) == "source":
            for file in files:
                if file.lower().endswith(".mka"):
                    full_path = os.path.join(root, file)
                    relative_path = os.path.relpath(full_path, subfolder_path)
                    mka_files.append((full_path, relative_path))
    
    return mka_files

def compute_output_path(input_path: str, subfolder_root: str) -> str:
    """
    Compute output path. If input is:
        /mnt/share/audiobooks/Hörspiele/Author/Series/Folder/source/file.mka
    Output should be:
        /mnt/share/audiobooks/Hörspiele/Author/Series/Folder/file.m4a
    
    i.e., sibling of the source folder (parent of parent), with .m4a extension.
    """
    input_path_obj = Path(input_path)
    filename = input_path_obj.stem  # filename without .mka
    
    # Get the parent directory of the immediate parent
    # e.g., if input is /path/to/Folder/source/file.mka,
    # we want /path/to/Folder/file.m4a
    output_dir = input_path_obj.parent.parent
    output_path = output_dir / f"{filename}.m4a"
    
    return str(output_path)

def m4a_file_exists_in_subfolder(mount_point: str, subfolder: str, filename_stem: str) -> bool:
    """
    Check if a .m4a file with the given stem exists anywhere in the subfolder recursively.
    """
    subfolder_path = os.path.join(mount_point, subfolder)
    target_name = f"{filename_stem}.m4a"
    
    for root, _, files in os.walk(subfolder_path):
        if target_name in files:
            logger.info(f"Found existing .m4a file: {os.path.join(root, target_name)}")
            return True
    
    return False

def copy_to_local_tmp(file_path: str, tmp_dir: str) -> str:
    """Copy file from mount point to local tmp directory."""
    filename = os.path.basename(file_path)
    local_path = os.path.join(tmp_dir, filename)
    shutil.copy2(file_path, local_path)
    return local_path

def convert_mka_to_m4a(local_mka: str, bitrate: str, script_dir: str) -> Optional[str]:
    """
    Convert .mka file using mka_to_aac.py script.
    Returns path to output .m4a file if successful, None otherwise.
    """
    script_path = os.path.join(script_dir, "mka_to_aac.py")
    
    if not os.path.isfile(script_path):
        logger.error(f"Conversion script not found: {script_path}")
        return None
    
    tmp_dir = os.path.dirname(local_mka)
    
    try:
        # Do not capture output so converter progress/heartbeat is visible live.
        subprocess.run(
            [sys.executable, script_path, local_mka, bitrate],
            cwd=tmp_dir,
            check=True,
            timeout=3600  # 1 hour timeout
        )
        mka_stem = Path(local_mka).stem
        m4a_file = os.path.join(tmp_dir, f"{mka_stem}.m4a")
        
        if os.path.isfile(m4a_file):
            logger.info(f"Conversion successful: {m4a_file}")
            return m4a_file
        else:
            logger.error("Conversion script did not produce output file")
            return None
    except subprocess.CalledProcessError as e:
        logger.error(f"Conversion failed for {local_mka} (exit code {e.returncode})")
        return None
    except subprocess.TimeoutExpired:
        logger.error(f"Conversion timeout for {local_mka}")
        return None

def copy_m4a_to_samba(local_m4a: str, output_samba_path: str) -> bool:
    """Copy converted .m4a file to Samba share."""
    try:
        os.makedirs(os.path.dirname(output_samba_path), exist_ok=True)
        shutil.copy2(local_m4a, output_samba_path)
        logger.info(f"Copied to Samba: {output_samba_path}")
        return True
    except Exception as e:
        logger.error(f"Failed to copy {local_m4a} to {output_samba_path}: {e}")
        return False

def cleanup_duplicate_formats(output_path: str, mount_point: str, subfolder: str) -> None:
    """
    Delete any .opus or .mka files with the same basename in the output directory.
    """
    output_dir = os.path.dirname(output_path)
    filename_stem = Path(output_path).stem
    
    for ext in [".opus", ".mka"]:
        duplicate_file = os.path.join(output_dir, f"{filename_stem}{ext}")
        if os.path.isfile(duplicate_file):
            try:
                os.remove(duplicate_file)
                logger.info(f"Deleted duplicate: {duplicate_file}")
            except Exception as e:
                logger.warning(f"Failed to delete {duplicate_file}: {e}")

def process_file(
    mka_path: str,
    input_relative_path: str,
    subfolder: str,
    bitrate: str,
    mount_point: str,
    script_dir: str
) -> bool:
    """
    Process a single .mka file: check, convert, copy, cleanup.
    Returns True if processed successfully, False otherwise.
    """
    filename_stem = Path(mka_path).stem
    
    # Check if .m4a already exists in the subfolder
    if m4a_file_exists_in_subfolder(mount_point, subfolder, filename_stem):
        logger.info(f"Skipping {input_relative_path} (m4a already exists)")
        return True
    
    logger.info(f"Processing: {input_relative_path}")
    
    # Create local tmp directory for this conversion
    with tempfile.TemporaryDirectory(prefix="mka_convert_") as tmp_dir:
        try:
            # Copy to local tmp
            local_mka = copy_to_local_tmp(mka_path, tmp_dir)
            logger.debug(f"Copied to local tmp: {local_mka}")
            
            # Convert
            local_m4a = convert_mka_to_m4a(local_mka, bitrate, script_dir)
            if not local_m4a:
                logger.error(f"Conversion failed: {input_relative_path}")
                return False
            
            # Compute output path on Samba
            output_samba_path = compute_output_path(mka_path, mount_point)
            
            # Copy to Samba
            if not copy_m4a_to_samba(local_m4a, output_samba_path):
                logger.error(f"Failed to copy output to Samba: {output_samba_path}")
                return False
            
            # Cleanup duplicate formats
            cleanup_duplicate_formats(output_samba_path, mount_point, subfolder)
            
            logger.info(f"Successfully processed: {input_relative_path}")
            return True
        
        except Exception as e:
            logger.error(f"Unexpected error processing {input_relative_path}: {e}")
            return False

def main() -> None:
    script_dir = os.path.dirname(os.path.abspath(__file__))
    try:
        # Prompt for credentials
        logger.info("Samba Share Audio Converter")
        logger.info("=" * 60)
        print()
        username = input("Samba username: ").strip()
        password = getpass("Samba password: ")
        
        if not username or not password:
            logger.error("Username and password are required")
            sys.exit(1)
        
        credentials = (username, password)
        
        total_files = 0
        processed_files = 0
        
        for share_name, subfolders, bitrate in SHARE_CONFIGS:
            mount_point: Optional[str] = None
            try:
                logger.info(f"\nConnecting to //{SMB_SERVER}/{share_name}...")
                mount_point = mount_samba_share(SMB_SERVER, share_name, credentials)
            except RuntimeError as e:
                logger.error(
                    f"Skipping share '{share_name}' because mount failed: {e}"
                )
                continue
            try:

                for subfolder in subfolders:
                    display_subfolder = subfolder if subfolder else "/"
                    logger.info(
                        f"\nProcessing share '{share_name}', subfolder: {display_subfolder} "
                        f"(bitrate: {bitrate})"
                    )

                    # Find all .mka files
                    mka_files = find_mka_files(mount_point, subfolder)

                    if not mka_files:
                        logger.info(
                            f"No .mka files found in share '{share_name}' "
                            f"subfolder '{display_subfolder}'"
                        )
                        continue

                    logger.info(f"Found {len(mka_files)} .mka file(s)")

                    # Process each file
                    for full_path, relative_path in mka_files:
                        total_files += 1
                        if process_file(
                            full_path,
                            relative_path,
                            subfolder,
                            bitrate,
                            mount_point,
                            script_dir
                        ):
                            processed_files += 1
            finally:
                if mount_point:
                    unmount_samba_share(mount_point)
        
        # Summary
        logger.info("\n" + "=" * 60)
        logger.info(f"Summary: {processed_files}/{total_files} files processed successfully")
    except KeyboardInterrupt:
        logger.info("\nCancelled by user")
        sys.exit(0)
    except Exception as e:
        logger.error(f"Fatal error: {e}", exc_info=True)
        sys.exit(1)
    finally:
        pass

if __name__ == "__main__":
    main()
