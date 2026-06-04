#!/bin/bash

# Optional: operator-supplied expected hash. If provided, the locally-built WASM
# must match before upload. This catches "wrong file built" / toolchain-skew
# scenarios where the canister-side checks alone wouldn't help.
EXPECTED_HASH="${1:-}"

# Helper: abort the script with a clear error message.
abort() {
    echo "" >&2
    echo "ABORT: $1" >&2
    echo "" >&2
    exit 1
}

# Check if Rust is installed
if ! command -v rustc &> /dev/null; then
    echo "Installing Rust..."
    curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y
    # Add Rust to current shell environment
    source "$HOME/.cargo/env"
else
    echo "Rust is already installed"
fi

# Create or update wasm_checker project
echo "Setting up wasm_checker project..."
if [ ! -d "wasm_checker" ]; then
    mkdir -p wasm_checker
    cd wasm_checker
    cargo init --bin
else
    cd wasm_checker
fi

# Update Cargo.toml for wasm_checker
echo "Updating wasm_checker dependencies..."
cat > Cargo.toml << 'EOF'
[package]
name = "wasm_checker"
version = "0.1.0"
edition = "2021"
EOF

# Update main.rs for wasm_checker
echo "Updating wasm_checker code..."
cat > src/main.rs << 'EOF'
use std::fs::File;
use std::io::Read;
use std::path::Path;

#[derive(Debug)]
enum WasmEncoding {
    Wasm,
    Gzip,
}

#[derive(Debug)]
#[allow(dead_code)]
enum WasmValidationError {
    DecodingError(String),
    IoError(std::io::Error),
}

impl From<std::io::Error> for WasmValidationError {
    fn from(err: std::io::Error) -> Self {
        WasmValidationError::IoError(err)
    }
}

fn wasm_encoding_and_size(module_bytes: &[u8]) -> Result<(WasmEncoding, usize), WasmValidationError> {
    // \0asm is WebAssembly module magic bytes
    if module_bytes.starts_with(b"\x00asm") {
        return Ok((WasmEncoding::Wasm, module_bytes.len()));
    }

    // 1f 8b is GZIP magic number, 08 is DEFLATE algorithm
    if module_bytes.starts_with(b"\x1f\x8b\x08") {
        if module_bytes.len() < 16 {
            return Err(WasmValidationError::DecodingError(
                "invalid Wasm module: gzip stream is too short".to_string(),
            ));
        }

        let mut isize_bytes = [0u8; 4];
        isize_bytes.copy_from_slice(&module_bytes[module_bytes.len() - 4..module_bytes.len()]);
        let uncompressed_size = u32::from_le_bytes(isize_bytes) as usize;
        return Ok((WasmEncoding::Gzip, uncompressed_size));
    }

    Err(WasmValidationError::DecodingError(
        "unsupported canister module format".to_string(),
    ))
}

fn main() -> Result<(), Box<dyn std::error::Error>> {
    let args: Vec<String> = std::env::args().collect();
    if args.len() != 2 {
        eprintln!("Usage: {} <wasm_file_path>", args[0]);
        std::process::exit(1);
    }

    let path = Path::new(&args[1]);
    let mut file = File::open(path)?;
    let mut wasm_data = Vec::new();
    file.read_to_end(&mut wasm_data)?;

    match wasm_encoding_and_size(&wasm_data) {
        Ok((encoding, size)) => {
            println!("WASM file encoding: {:?}", encoding);
            println!("Size: {} bytes", size);
        }
        Err(e) => {
            eprintln!("Error: {:?}", e);
            std::process::exit(1);
        }
    }

    Ok(())
}
EOF

# Build wasm_checker
echo "Building wasm_checker..."
cargo build --release
cd ..

# Create or update upload_pool_wasm project
echo "Setting up Rust project..."
if [ ! -d "upload_pool_wasm" ]; then
    mkdir -p upload_pool_wasm
    cd upload_pool_wasm
    cargo init --bin
else
    cd upload_pool_wasm
fi

# Update Cargo.toml
echo "Updating dependencies..."
cat > Cargo.toml << 'EOF'
[package]
name = "upload_pool_wasm"
version = "0.1.0"
edition = "2021"

[dependencies]
sha2 = "0.10"
EOF

# Update main.rs
echo "Updating Rust code..."
cat > src/main.rs << 'EOF'
use std::fs::File;
use std::io::Read;
use std::path::Path;
use sha2::{Sha256, Digest};

const CHUNK_SIZE: usize = 200 * 1024; // 200KB

fn main() -> Result<(), Box<dyn std::error::Error>> {
    // Get parent directory
    let current_dir = std::env::current_dir()?;
    let parent_dir = current_dir.parent().unwrap();
    let wasm_path = parent_dir.join(".dfx/local/canisters/SwapPool/SwapPool.wasm");
    
    println!("SwapPool.wasm absolute path: {}", wasm_path.display());
    
    let path = Path::new(&wasm_path);
    
    // Read WASM file
    let mut file = File::open(path)?;
    let mut wasm_data = Vec::new();
    file.read_to_end(&mut wasm_data)?;
    
    // Calculate SHA256
    let mut hasher = Sha256::new();
    hasher.update(&wasm_data);
    let sha256 = hasher.finalize();
    eprintln!("WASM file SHA256 hash: {:x}", sha256);
    
    // Split file and output each chunk
    let total_chunks = (wasm_data.len() + CHUNK_SIZE - 1) / CHUNK_SIZE;
    println!("{}", total_chunks); // Output number of chunks
    
    for i in 0..total_chunks {
        let start = i * CHUNK_SIZE;
        let end = std::cmp::min((i + 1) * CHUNK_SIZE, wasm_data.len());
        let chunk = &wasm_data[start..end];
        
        // Output debug info
        eprintln!("Chunk {} size: {}", i, chunk.len());
        
        // Output bytes in Candid format
        let nat8_array: String = chunk.iter()
            .map(|b| b.to_string())
            .collect::<Vec<String>>()
            .join(";");
        println!("{}", nat8_array);
        
        if i == 0 {
            eprintln!("First chunk last 10 bytes: {:?}", &chunk[chunk.len().saturating_sub(10)..]);
        }
        if i == 1 {
            eprintln!("Second chunk first 10 bytes: {:?}", &chunk[..10.min(chunk.len())]);
        }
    }
    
    Ok(())
}
EOF

# Build the program
echo "Building the program..."
cargo build --release

# Create temporary directory
TEMP_DIR=$(mktemp -d)
echo "Temp directory: $TEMP_DIR"
trap 'rm -rf "$TEMP_DIR"' EXIT

# Get number of chunks and all chunk data
./target/release/upload_pool_wasm > "$TEMP_DIR/chunks.txt"

# Get number of chunks (now on the second line)
total_chunks=$(sed -n '2p' "$TEMP_DIR/chunks.txt")

# Read and upload each chunk
for i in $(seq 1 $total_chunks); do
    echo "Uploading chunk $i/$total_chunks..."
    # Get current chunk data
    chunk_data=$(sed -n "$((i+2))p" "$TEMP_DIR/chunks.txt" | tr -d '\n' | sed 's/;$//')
    # Upload chunk
    dfx canister call SwapPoolInstaller uploadWasmChunk "(vec { $chunk_data })"
    dfx canister call SwapFactory uploadWasmChunk "(vec { $chunk_data })"
    if [ $? -ne 0 ]; then
        echo "Error uploading chunk $i"
        exit 1
    fi
    if [ $i -eq 1 ] || [ $i -eq 2 ]; then
        echo "Chunk $i data (first 20 bytes):"
        echo "$chunk_data" | awk -F';' '{for(i=1;i<=20&&i<=NF;i++)printf "%s ",$i; print ""}'
    fi
done

# Combine all chunks
echo "Combining WASM chunks..."
dfx canister call SwapPoolInstaller combineWasmChunks
dfx canister call SwapFactory combineWasmChunks

# ---- HASH-GATED ACTIVATION ----
# Compute the locally-built WASM hash. This is the authoritative hash used to
# gate activation: staging blobs in both canisters must match it BEFORE any
# activateWasm call. After activation, active blobs must match it as well.
cd ..
LOCAL_WASM_HASH=$(sha256sum ".dfx/local/canisters/SwapPool/SwapPool.wasm" | awk '{print $1}')
echo "Local WASM SHA256: $LOCAL_WASM_HASH"
cd upload_pool_wasm

# If operator supplied an expected hash, verify the locally-built WASM matches
# it BEFORE uploading anything to the canisters. Catches the case where the
# build artifact is stale or from a different source than the operator intended.
if [ -n "$EXPECTED_HASH" ]; then
    if [ "$LOCAL_WASM_HASH" != "$EXPECTED_HASH" ]; then
        abort "Local WASM hash $LOCAL_WASM_HASH does not match operator-supplied expected hash $EXPECTED_HASH. The local build is not what you committed to ship."
    fi
    echo "Operator-supplied expected hash matches local build."
else
    echo "WARNING: no expected hash supplied as first argument; skipping pre-upload hash gate." >&2
    echo "         Pass the SHA256 of the WASM you intend to ship as the first argument to enable it." >&2
fi

# Verify staging blob in each canister matches the local hash BEFORE activation.
# This catches in-transit chunk corruption, wrong-file uploads, and concurrent
# uploader races. If we activate before this check, a corrupt blob becomes the
# active WASM and contaminates every subsequent pool deploy and upgrade.
echo "Verifying staging WASM hashes BEFORE activation..."

dfx canister call SwapPoolInstaller getStagingWasm | sed 's/blob "//;s/"//g' | xxd -r -p > installer_staging.wasm
INSTALLER_STAGING_HASH=$(sha256sum installer_staging.wasm | awk '{print $1}')
if [ "$INSTALLER_STAGING_HASH" != "$LOCAL_WASM_HASH" ]; then
    abort "SwapPoolInstaller staging WASM hash $INSTALLER_STAGING_HASH does not match local $LOCAL_WASM_HASH. NOT activating. Re-run upload after investigating the corruption."
fi
echo "  SwapPoolInstaller staging hash OK: $INSTALLER_STAGING_HASH"

dfx canister call SwapFactory getStagingWasm | sed 's/blob "//;s/"//g' | xxd -r -p > factory_staging.wasm
FACTORY_STAGING_HASH=$(sha256sum factory_staging.wasm | awk '{print $1}')
if [ "$FACTORY_STAGING_HASH" != "$LOCAL_WASM_HASH" ]; then
    abort "SwapFactory staging WASM hash $FACTORY_STAGING_HASH does not match local $LOCAL_WASM_HASH. NOT activating. Re-run upload after investigating the corruption."
fi
echo "  SwapFactory staging hash OK: $FACTORY_STAGING_HASH"

# Activate wasm file (only reached if both staging hashes verified above).
echo "Activating WASM..."
dfx canister call SwapPoolInstaller activateWasm
dfx canister call SwapFactory activateWasm

# Check WASM encoding and size of the source artifact.
echo "Checking WASM encoding and size..."
cd ..
./wasm_checker/target/release/wasm_checker .dfx/local/canisters/SwapPool/SwapPool.wasm
cd upload_pool_wasm

# Verify active blob in each canister also matches the local hash. Defends
# against any race where activation reads from somewhere other than the
# verified staging blob.
echo "Verifying active WASM hashes after activation..."

dfx canister call SwapPoolInstaller getActiveWasm | sed 's/blob "//;s/"//g' | xxd -r -p > installer_active.wasm
echo "Checking SwapPoolInstaller WASM encoding and size..."
cd ..
./wasm_checker/target/release/wasm_checker upload_pool_wasm/installer_active.wasm
cd upload_pool_wasm
INSTALLER_WASM_HASH=$(sha256sum installer_active.wasm | awk '{print $1}')
echo "  SwapPoolInstaller active SHA256: $INSTALLER_WASM_HASH"
if [ "$INSTALLER_WASM_HASH" != "$LOCAL_WASM_HASH" ]; then
    abort "SwapPoolInstaller active WASM hash $INSTALLER_WASM_HASH does not match local $LOCAL_WASM_HASH after activation. The fleet is now contaminated; re-upload immediately."
fi

dfx canister call SwapFactory getActiveWasm | sed 's/blob "//;s/"//g' | xxd -r -p > factory_active.wasm
echo "Checking SwapFactory WASM encoding and size..."
cd ..
./wasm_checker/target/release/wasm_checker upload_pool_wasm/factory_active.wasm
cd upload_pool_wasm
FACTORY_WASM_HASH=$(sha256sum factory_active.wasm | awk '{print $1}')
echo "  SwapFactory active SHA256: $FACTORY_WASM_HASH"
if [ "$FACTORY_WASM_HASH" != "$LOCAL_WASM_HASH" ]; then
    abort "SwapFactory active WASM hash $FACTORY_WASM_HASH does not match local $LOCAL_WASM_HASH after activation. The fleet is now contaminated; re-upload immediately."
fi

# Clean up generated files
echo "Cleaning up..."
cd ..
rm -rf upload_pool_wasm
rm -rf wasm_checker

echo "WASM upload completed successfully (hash $LOCAL_WASM_HASH)!"