#!/usr/bin/env python3
"""Python po2lmo - Compile .po to .lmo (ImmortalWrt/OpenWrt format).
Usage: python3 po2lmo.py input.po output.lmo
"""
import struct, sys, os

def sfh_hash(data):
    """SFH hash as used by po2lmo. Args: data = bytes to hash."""
    n = len(data)
    h = n ^ n  # init = n, so h = n ^ n = 0
    rem = n & 3
    n >>= 2  # number of full uint32 words
    for i in range(n):
        v = struct.unpack('<I', data[i*4:(i+1)*4])[0]
        h ^= v
    for i in range(rem):
        h ^= data[n*4 + i]
        h ^= h >> 16
    h ^= h >> 10
    h ^= h >> 4
    h ^= (h & 0x80000000) >> 1 if h & 0x80000000 else 0
    h ^= (h & 0x0000ffff) << 5 if h & 0x0000ffff else 0
    return h & 0xffffffff

def extract_string(line):
    """Extract content from quoted string."""
    line = line.strip()
    if not line or line[0] == '#':
        return None
    # Find first and last quote
    start = line.find('"')
    end = line.rfind('"')
    if start < 0 or end < 0 or end <= start:
        return None
    content = line[start+1:end]
    # Unescape
    result = []
    i = 0
    while i < len(content):
        if content[i] == '\\' and i + 1 < len(content):
            nxt = content[i+1]
            if nxt == 'n':
                result.append('\n')
            elif nxt == 't':
                result.append('\t')
            elif nxt == '\\':
                result.append('\\')
            elif nxt == '"':
                result.append('"')
            else:
                result.append(nxt)
            i += 2
        else:
            result.append(content[i])
            i += 1
    return ''.join(result)

def compile_po(input_path, output_path):
    entries = []  # (key_id, translation_bytes)
    with open(input_path, 'r', encoding='utf-8') as f:
        lines = f.readlines()
    
    i = 0
    while i < len(lines):
        line = lines[i]
        # Skip comments and empty lines
        if line.strip() == '' or line.strip().startswith('#'):
            i += 1
            continue
        
        # msgid
        if line.startswith('msgid "'):
            msgid_parts = []
            msgid_first = extract_string(line)
            if msgid_first is not None:
                msgid_parts.append(msgid_first)
            i += 1
            # Continuation lines (lines starting with "msgstr" etc. break out)
            while i < len(lines):
                stripped = lines[i].strip()
                if not stripped or stripped.startswith('#'):
                    break
                if stripped.startswith(('msgstr', 'msgid_plural', 'msgctxt')):
                    break
                cont = extract_string(lines[i])
                if cont is not None:
                    msgid_parts.append(cont)
                    i += 1
                else:
                    break
            
            msgid = ''.join(msgid_parts)
            
            # Skip msgid_plural if present
            if i < len(lines) and lines[i].startswith('msgid_plural'):
                i += 1
                while i < len(lines):
                    cont = extract_string(lines[i])
                    if cont is not None:
                        i += 1
                    else:
                        break
            
            # msgstr
            if i < len(lines) and (lines[i].startswith('msgstr "') or lines[i].startswith('msgstr[')):
                msgstr_parts = []
                msgstr_first = extract_string(lines[i])
                if msgstr_first is not None:
                    msgstr_parts.append(msgstr_first)
                i += 1
                while i < len(lines):
                    stripped = lines[i].strip()
                    if not stripped or stripped.startswith('#'):
                        break
                    if stripped.startswith(('msgid', 'msgctxt', 'msgstr[')):
                        break
                    cont = extract_string(lines[i])
                    if cont is not None:
                        msgstr_parts.append(cont)
                        i += 1
                    else:
                        break
                
                msgstr = ''.join(msgstr_parts)
                
                # Skip header entry (msgid "") and entries where hash matches
                if msgid and msgstr:
                    key_data = msgid.encode('utf-8')
                    trans_data = msgstr.encode('utf-8')
                    key_id = sfh_hash(key_data)
                    val_id = sfh_hash(trans_data)
                    if key_id != val_id:  # Only add if hash differs (same as C logic)
                        entries.append((key_id, trans_data))
            else:
                i += 1
        else:
            i += 1
    
    # Sort by key_id (same as C's qsort with cmp_index)
    entries.sort(key=lambda x: x[0])
    
    # Build the file
    buf = bytearray()
    index = []
    offset = 0
    
    for key_id, trans_data in entries:
        # Write translation string, padded to 4 bytes
        buf.extend(trans_data)
        pad = (4 - (len(trans_data) % 4)) % 4
        buf.extend(b'\x00' * pad)
        
        index.append({
            'key_id': key_id,
            'val_id': sfh_hash(trans_data),
            'offset': offset,
            'length': len(trans_data)
        })
        offset += len(trans_data) + pad
    
    # Write index (big-endian)
    for entry in index:
        buf.extend(struct.pack('>IIII', entry['key_id'], entry['val_id'], entry['offset'], entry['length']))
    
    # Write total_offset (big-endian)
    buf.extend(struct.pack('>I', offset))
    
    with open(output_path, 'wb') as f:
        f.write(buf)

if __name__ == '__main__':
    if len(sys.argv) != 3:
        print(f"Usage: {sys.argv[0]} input.po output.lmo")
        sys.exit(1)
    compile_po(sys.argv[1], sys.argv[2])
    out_size = os.path.getsize(sys.argv[2])
    print(f"  ✅ po2lmo: {out_size} bytes")
