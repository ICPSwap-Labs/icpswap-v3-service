import Nat "mo:base/Nat";
import Blob "mo:base/Blob";
import Hash "mo:base/Hash";
import Buffer "mo:base/Buffer";
import HashMap "mo:base/HashMap";
import Prim "mo:⛔";
import Iter "mo:base/Iter";

module {
    public type Chunk = [Nat8];

    private func _hash(n: Nat) : Hash.Hash { Prim.natToNat32(n) };

    public class Service(initWasmBlob: Blob) {
        private let MAX_WASM_SIZE : Nat = 4 * 1024 * 1024;  // 4MB
        private var chunksMap = HashMap.HashMap<Nat, Chunk>(1, Nat.equal, _hash);
        private var nextChunkID = 0;
        private var stagingWasmBlob : Blob = Blob.fromArray([]);
        private var activeWasmBlob : Blob = initWasmBlob;

        /// Step 1: Upload a single chunk of WASM code
        /// Returns the assigned chunk ID
        public func uploadChunk(chunk : Chunk) : Nat {
            assert(chunk.size() > 0);
            nextChunkID += 1;
            chunksMap.put(nextChunkID, chunk);
            nextChunkID;
        };

        /// Step 2: Combine all uploaded chunks into a staging WASM blob
        /// Chunks are combined in order of their IDs
        public func combineChunks() : () {
            var contentChunksList = Buffer.Buffer<Nat8>(0);
            var totalLength = 0;
            
            // Get all chunks in order
            for (i in Iter.range(1, nextChunkID)) {
                let chunk : ?Chunk = chunksMap.get(i);
                switch (chunk) {
                    case (?content) {
                        totalLength += content.size();
                        for (byte in content.vals()) {
                            contentChunksList.add(byte);
                        };
                    };
                    case null {};
                };
            };

            let contentBytes = Buffer.toArray(contentChunksList);
            assert (contentBytes.size() > 0);
            assert (totalLength <= MAX_WASM_SIZE);

            stagingWasmBlob := Blob.fromArray(contentBytes);
        };

        /// Step 3: Activate the staging WASM blob
        /// This will make the staging blob the active one and clear the staging area
        public func activateWasm() : () {
            activeWasmBlob := stagingWasmBlob;
            stagingWasmBlob := Blob.fromArray([]);
            chunksMap := HashMap.HashMap<Nat, Chunk>(1, Nat.equal, _hash);
            nextChunkID := 0;
        };

        /// Clear all chunks
        public func clearChunks() : () {
            chunksMap := HashMap.HashMap<Nat, Chunk>(1, Nat.equal, _hash);
            nextChunkID := 0;
        };

        /// Get the current staging WASM blob
        public func getStagingWasm() : Blob {
            stagingWasmBlob;
        };

        /// Get the currently active WASM blob
        public func getActiveWasm() : Blob {
            activeWasmBlob;
        };

    };
}; 