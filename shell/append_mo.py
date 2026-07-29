#!/usr/bin/env python3
"""Append a translation entry to an existing .lmo (MO format) file."""
import struct, sys, os

def write_mo(output_path, entries):
    """Write MO file with entries list of (msgid, msgstr) tuples"""
    count = len(entries)
    header_size = 28                      # 7 x uint32
    orig_table_off = header_size          # start of orig table
    trans_table_off = header_size + count * 8  # start of trans table
    string_start   = header_size + count * 16  # start of string data

    # Build string data
    orig_bytes_list = [(e[0].encode('utf-8') + b'\x00') for e in entries]
    trans_bytes_list = [(e[1].encode('utf-8') + b'\x00') for e in entries]
    orig_data = b''.join(orig_bytes_list)
    trans_data = b''.join(trans_bytes_list)

    # Compute offsets for each entry within string data
    orig_offsets = []
    sofar = 0
    for ob in orig_bytes_list:
        orig_offsets.append(string_start + sofar)
        sofar += len(ob)
    trans_offsets = []
    sofar = 0
    for tb in trans_bytes_list:
        trans_offsets.append(string_start + len(orig_data) + sofar)
        sofar += len(tb)

    # Build header
    buf  = struct.pack('<I', 0x950412de)  # magic
    buf += struct.pack('<I', 0)            # version
    buf += struct.pack('<I', count)        # count
    buf += struct.pack('<I', orig_table_off)
    buf += struct.pack('<I', trans_table_off)
    buf += struct.pack('<I', 0)            # hash table size
    buf += struct.pack('<I', 0)            # hash table offset

    # Orig table: (length, offset) pairs
    for i, ob in enumerate(orig_bytes_list):
        buf += struct.pack('<I', len(ob))
        buf += struct.pack('<I', orig_offsets[i])

    # Trans table: (length, offset) pairs
    for i, tb in enumerate(trans_bytes_list):
        buf += struct.pack('<I', len(tb))
        buf += struct.pack('<I', trans_offsets[i])

    # String data
    buf += orig_data + trans_data

    with open(output_path, 'wb') as f:
        f.write(buf)

if __name__ == '__main__':
    input_path, new_msgid, new_msgstr, output_path = sys.argv[1], sys.argv[2], sys.argv[3], sys.argv[4]
    entries = []
    if input_path and os.path.exists(input_path) and os.path.getsize(input_path) > 0:
        with open(input_path, 'rb') as f:
            data = f.read()
        magic = struct.unpack_from('<I', data, 0)[0]
        if magic not in (0x950412de, 0xde120495, 0x756c706e):
            # Try big-endian read
            magic_be = struct.unpack_from('>I', data, 0)[0]
            if magic_be not in (0x950412de, 0xde120495, 0x756c706e):
                print(f"  ⚠️ Unknown format magic: {magic:#x}")
                # Still try - structure might be identical
        count = struct.unpack_from('<I', data, 8)[0]
        orig_off = struct.unpack_from('<I', data, 12)[0]
        trans_off = struct.unpack_from('<I', data, 16)[0]
        for i in range(count):
            slen = struct.unpack_from('<I', data, orig_off + i*8)[0]
            soff = struct.unpack_from('<I', data, orig_off + i*8 + 4)[0]
            msgid = data[soff:soff+slen].rstrip(b'\x00').decode('utf-8')
            slen = struct.unpack_from('<I', data, trans_off + i*8)[0]
            soff = struct.unpack_from('<I', data, trans_off + i*8 + 4)[0]
            msgstr = data[soff:soff+slen].rstrip(b'\x00').decode('utf-8')
            entries.append((msgid, msgstr))

    found = False
    for i, (mid, _) in enumerate(entries):
        if mid == new_msgid:
            entries[i] = (new_msgid, new_msgstr)
            found = True
            break
    if not found:
        entries.append((new_msgid, new_msgstr))

    write_mo(output_path, entries)
    print(f"  ✅ MO file: {len(entries)} entries -> {os.path.getsize(output_path)} bytes")
