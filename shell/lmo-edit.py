#!/usr/bin/env python3
"""Add a translation entry to an existing .lmo file (ImmortalWrt/OpenWrt format).
Usage: python3 lmo-edit.py input.lmo output.lmo msgid msgstr
"""
import struct, sys, os

def sfh_get16(data, offset=0):
    """Little-endian uint16 read (matches lmo.c:sfh_get16)"""
    return (data[offset+1] << 8) + data[offset]

def sfh_hash(data_bytes):
    """Exact sfh_hash from lmo.c (used by both po2lmo and luci runtime)"""
    MASK32 = 0xffffffff
    h = init_len = len(data_bytes)
    data = bytearray(data_bytes)
    n = len(data)
    rem = n & 3
    n >>= 2
    pos = 0
    for _ in range(n):
        h = (h + sfh_get16(data, pos)) & MASK32
        tmp = ((sfh_get16(data, pos+2) << 11) ^ h) & MASK32
        h = ((h << 16) ^ tmp) & MASK32
        pos += 4
        h = (h + (h >> 11)) & MASK32
    if rem == 3:
        h = (h + sfh_get16(data, pos)) & MASK32
        h ^= (h << 16) & MASK32
        val = data[pos+2]
        if val > 127: val -= 256
        h ^= (val << 18) & MASK32
        h = (h + (h >> 11)) & MASK32
    elif rem == 2:
        h = (h + sfh_get16(data, pos)) & MASK32
        h ^= (h << 11) & MASK32
        h = (h + (h >> 17)) & MASK32
    elif rem == 1:
        val = data[pos]
        if val > 127: val -= 256
        h = (h + val) & MASK32
        h ^= (h << 10) & MASK32
        h = (h + (h >> 1)) & MASK32
    h ^= (h << 3) & MASK32
    h = (h + (h >> 5)) & MASK32
    h ^= (h << 4) & MASK32
    h = (h + (h >> 17)) & MASK32
    h ^= (h << 25) & MASK32
    h = (h + (h >> 6)) & MASK32
    return h

def main():
    input_path, output_path, add_msgid, add_msgstr = sys.argv[1:5]
    add_key = sfh_hash(add_msgid.encode('utf-8'))
    add_val = sfh_hash(add_msgstr.encode('utf-8'))

    with open(input_path, 'rb') as f:
        data = bytearray(f.read())

    # Parse existing lmo
    total_off = struct.unpack_from('>I', data, len(data) - 4)[0]
    idx_size = len(data) - 4 - total_off
    n = idx_size // 16

    # Decode index entries
    entries = []
    for i in range(n):
        off = total_off + i * 16
        key_id = struct.unpack_from('>I', data, off)[0]
        val_id = struct.unpack_from('>I', data, off + 4)[0]
        str_off = struct.unpack_from('>I', data, off + 8)[0]
        str_len = struct.unpack_from('>I', data, off + 12)[0]
        entries.append((key_id, val_id, str_off, str_len))

    # Check if key already exists
    existing = [e for e in entries if e[0] == add_key]
    if existing:
        so, sl = existing[0][2], existing[0][3]
        existing_trans = str(data[so:so+sl], 'utf-8')
        print(f"  Key exists: '{existing_trans}' → skipping")
        # Copy as-is
        with open(output_path, 'wb') as f:
            f.write(data)
        print(f"  ✅ Copied {os.path.getsize(output_path)} bytes (unchanged)")
        return

    # Append new translation string (padded to 4 bytes) into string data area
    trans_bytes = add_msgstr.encode('utf-8')
    pad = (4 - (len(trans_bytes) % 4)) % 4
    insert_data = bytes(trans_bytes) + b'\x00' * pad
    insert_len = len(trans_bytes)

    # Add new entry to list and sort by key_id (required for binary search)
    entries.append((add_key, add_val, total_off, insert_len))
    entries.sort(key=lambda x: x[0])

    # Build new string data area: old + new
    new_str_data = bytearray(data[:total_off])
    new_str_data.extend(insert_data)
    new_total_off = len(new_str_data)

    # Rebuild sorted index (each entry: key_id|val_id|offset|length, BE)
    new_index = bytearray()
    for e in entries:
        new_index.extend(struct.pack('>IIII', e[0], e[1], e[2], e[3]))

    # Build output: sorted string data + sorted index + total_offset
    out = bytearray()
    out.extend(new_str_data)
    out.extend(new_index)
    out.extend(struct.pack('>I', new_total_off))

    with open(output_path, 'wb') as f:
        f.write(out)

    new_n = n + 1
    print(f"  ✅ Added entry: 0x{add_key:08x} → '{add_msgstr}' ({new_n} total entries, {os.path.getsize(output_path)} bytes)")

if __name__ == '__main__':
    main()
