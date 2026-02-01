# -*- mode: python ; coding: utf-8 -*-
"""
PyInstaller spec file for STaBioM CLI.

Build with:
    pyinstaller stabiom.spec

This creates a one-folder bundle in dist/stabiom/ containing:
    - stabiom (executable)
    - main/pipelines/
    - main/configs/
    - main/schemas/
    - main/R/
    - main/compare/
    - main/data/ (optional reference data)
"""

import os
from pathlib import Path

# Get the repo root (where this spec file lives)
REPO_ROOT = Path(SPECPATH)
MAIN_DIR = REPO_ROOT / "main"


def collect_data_files():
    """Collect all data files to bundle with the executable."""
    datas = []

    # Include certifi CA bundle for SSL certificate verification
    try:
        import certifi
        certifi_path = Path(certifi.where())
        if certifi_path.exists():
            # Add the cacert.pem file to certifi package location
            datas.append((str(certifi_path), "certifi"))
    except ImportError:
        pass

    # Pipeline shell scripts
    pipelines_dir = MAIN_DIR / "pipelines"
    if pipelines_dir.exists():
        for f in pipelines_dir.rglob("*.sh"):
            rel_path = f.relative_to(REPO_ROOT)
            datas.append((str(f), str(rel_path.parent)))

    # Include Dockerfiles for building container images
    container_dir = MAIN_DIR / "pipelines" / "container"
    if container_dir.exists():
        for f in container_dir.glob("dockerfile.*"):
            rel_path = f.relative_to(REPO_ROOT)
            datas.append((str(f), str(rel_path.parent)))

    # Config files
    configs_dir = MAIN_DIR / "configs"
    if configs_dir.exists():
        for f in configs_dir.glob("*.json"):
            datas.append((str(f), "main/configs"))

    # Schema files
    schemas_dir = MAIN_DIR / "schemas"
    if schemas_dir.exists():
        for f in schemas_dir.glob("*.json"):
            datas.append((str(f), "main/schemas"))

    # R scripts for visualization
    r_dir = MAIN_DIR / "R"
    if r_dir.exists():
        for f in r_dir.rglob("*.R"):
            rel_path = f.relative_to(REPO_ROOT)
            datas.append((str(f), str(rel_path.parent)))

    # Compare module Python files
    compare_dir = MAIN_DIR / "compare"
    if compare_dir.exists():
        for f in compare_dir.rglob("*.py"):
            rel_path = f.relative_to(REPO_ROOT)
            datas.append((str(f), str(rel_path.parent)))
        # Also include any templates
        for f in compare_dir.rglob("*.html"):
            rel_path = f.relative_to(REPO_ROOT)
            datas.append((str(f), str(rel_path.parent)))
        for f in compare_dir.rglob("*.jinja2"):
            rel_path = f.relative_to(REPO_ROOT)
            datas.append((str(f), str(rel_path.parent)))

    # Tools directory (shell scripts and utilities)
    tools_dir = MAIN_DIR / "tools"
    if tools_dir.exists():
        for f in tools_dir.rglob("*"):
            if f.is_file() and not f.name.startswith("."):
                rel_path = f.relative_to(REPO_ROOT)
                datas.append((str(f), str(rel_path.parent)))

    # Data directory (reference databases, Valencia centroids, etc.)
    # Note: Large databases should be downloaded separately
    data_dir = MAIN_DIR / "data"
    if data_dir.exists():
        # Include small reference files (Valencia centroids, test data, etc.)
        for pattern in ["*.csv", "*.tsv", "*.json", "*.txt"]:
            for f in data_dir.rglob(pattern):
                # Skip very large files
                if f.stat().st_size < 10 * 1024 * 1024:  # < 10MB
                    rel_path = f.relative_to(REPO_ROOT)
                    datas.append((str(f), str(rel_path.parent)))

    return datas


# Collect all data files
datas = collect_data_files()

# Hidden imports that PyInstaller might miss
hiddenimports = [
    "cli",
    "cli.discovery",
    "cli.runner",
    "cli.progress",
    "cli.setup",
    "compare",
    "compare.src",
    "compare.src.compare",
    "main.compare",
    "main.compare.src",
    "main.compare.src.compare",
    "main.compare.src.harmonise",
    "main.compare.src.analysis",
    "main.compare.src.visualize",
    "main.compare.src.report",
    "main.compare.src.run_parser",
    "certifi",  # SSL certificates for HTTPS downloads
]

# Analysis
a = Analysis(
    ["cli/__main__.py"],
    pathex=[str(REPO_ROOT)],
    binaries=[],
    datas=datas,
    hiddenimports=hiddenimports,
    hookspath=[],
    hooksconfig={},
    runtime_hooks=[],
    excludes=[
        # Exclude packages not needed at runtime
        "tkinter",
        "matplotlib",
        "PIL",
        "pytest",
        "sphinx",
        "IPython",
        "jupyter",
        "notebook",
    ],
    noarchive=False,
    optimize=0,
)

# Create PYZ archive
pyz = PYZ(a.pure)

# Create executable
exe = EXE(
    pyz,
    a.scripts,
    [],
    exclude_binaries=True,
    name="stabiom",
    debug=False,
    bootloader_ignore_signals=False,
    strip=False,
    upx=True,
    console=True,
    disable_windowed_traceback=False,
    argv_emulation=False,
    target_arch=None,
    codesign_identity=None,
    entitlements_file=None,
)

# Create collection (one-folder distribution)
coll = COLLECT(
    exe,
    a.binaries,
    a.datas,
    strip=False,
    upx=True,
    upx_exclude=[],
    name="stabiom",
)
