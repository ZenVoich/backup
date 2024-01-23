// @testmode wasi

import {MemoryRegion} "mo:memory-region";
import Blob "mo:base/Blob";
import Debug "mo:base/Debug";

let memory_region = MemoryRegion.new();

let blob = Blob.fromArray([1, 2, 3, 4]);
let blob2 = Blob.fromArray([2, 2, 2, 3, 3]);

let address0 = MemoryRegion.addBlob(memory_region, blob);
let address = MemoryRegion.addBlob(memory_region, blob);

let b = MemoryRegion.loadBlob(memory_region, address, blob.size());

Debug.print(debug_show(Blob.toArray(b)));
Debug.print(debug_show(MemoryRegion.size_info(memory_region)));

MemoryRegion.deallocate(memory_region, address, blob.size());
MemoryRegion.deallocate(memory_region, address0, blob.size());
Debug.print(debug_show(MemoryRegion.size_info(memory_region)));

let address2 = MemoryRegion.addBlob(memory_region, blob2);

let b2 = MemoryRegion.loadBlob(memory_region, address2, blob2.size());
Debug.print(debug_show(Blob.toArray(b2)));
Debug.print(debug_show(MemoryRegion.size_info(memory_region)));