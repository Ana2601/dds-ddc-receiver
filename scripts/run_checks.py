#!/usr/bin/env python3
"""Drives the DDC simulation and checks it.

  1. bit-exact: every I/Q output sample equals the integer Python model of the chain
  2. NCO spectral purity: SFDR of the RTL's own cos/sin output (coherent FFT)
  3. receiver: a tone at f_nco + d comes out as a complex tone at +d; SFDR in the output band
  4. CIC response: measured RTL gain at several frequencies vs. the theoretical CIC response

Usage: run_checks.py <build dir> <compiled tb.vvp>
"""
import math
import subprocess
import sys

import numpy as np

N_STAGES, LR = 4, 4
R = 1 << LR
FAILS = []


def check(name, ok, detail):
    print(f"  [{'PASS' if ok else 'FAIL'}] {name}: {detail}")
    if not ok:
        FAILS.append(name)


# ----------------------------------------------------------------------------- golden model
def gen_lut(path):
    lut = [round(32767 * math.sin(math.pi / 2 * (i + 0.5) / 1024)) for i in range(1024)]
    with open(path, "w") as f:
        f.write("\n".join(f"{v:04x}" for v in lut) + "\n")
    return lut


def model(x, inc, lut):
    def sine(p):
        q, i = p >> 10, p & 0x3FF
        if q in (1, 3):
            i = 1023 - i
        v = lut[i]
        return -v if q >= 2 else v

    def rnd(prod):
        return ((prod + 16384) >> 15)

    def wrap16(v):
        v &= 0xFFFF
        return v - 0x10000 if v & 0x8000 else v

    W = 16 + N_STAGES * LR
    mask = (1 << W) - 1

    def sw(v):
        v &= mask
        return v - (1 << W) if v >> (W - 1) else v

    phase = 0
    ii, qq = [], []
    for s in x:
        p12 = phase >> 20
        c, sn = sine((p12 + 0x400) & 0xFFF), sine(p12)
        ii.append(wrap16(rnd(s * c)))
        qq.append(wrap16(-wrap16(rnd(s * sn))))
        phase = (phase + inc) & 0xFFFFFFFF

    def cic(v):
        integ, comb = [0] * N_STAGES, [0] * N_STAGES
        out = []
        for n, s in enumerate(v):
            new = [0] * N_STAGES
            new[0] = sw(integ[0] + s)
            for k in range(1, N_STAGES):
                new[k] = sw(integ[k] + integ[k - 1])
            if n % R == R - 1:
                c = integ[N_STAGES - 1]                     # value before this edge's update
                chain = [c]
                for k in range(N_STAGES):
                    chain.append(sw(chain[-1] - comb[k]))
                comb = chain[:N_STAGES]
                out.append(chain[-1] >> (N_STAGES * LR))
            integ = new
        return out

    return cic(ii), cic(qq)


# ----------------------------------------------------------------------------- helpers
def run(vvp, build, x, inc, gap=0, tag="run"):
    with open(f"{build}/{tag}_in.txt", "w") as f:
        f.write("\n".join(str(v) for v in x) + "\n")
    subprocess.run(["vvp", "-n", vvp, f"+in={build}/{tag}_in.txt", f"+out={build}/{tag}_out.txt",
                    f"+nco={build}/{tag}_nco.txt", f"+inc={inc:08x}", f"+gap={gap}"],
                   check=True, stdout=subprocess.DEVNULL)
    out = np.loadtxt(f"{build}/{tag}_out.txt", dtype=int, ndmin=2)
    nco = np.loadtxt(f"{build}/{tag}_nco.txt", dtype=int, ndmin=2)
    return out[:, 0], out[:, 1], nco[:, 0], nco[:, 1]


def sfdr_db(sig):
    """Spurious-free dynamic range of a complex signal (Blackman-Harris window)."""
    n = len(sig)
    w = np.blackman(n)
    spec = np.abs(np.fft.fft(sig * w)) ** 2
    k = int(np.argmax(spec))
    guard = 8
    mask = np.ones(n, bool)
    mask[[(k + d) % n for d in range(-guard, guard + 1)]] = False
    mask[[d % n for d in range(-guard, guard + 1)]] = False            # ignore DC
    return 10 * math.log10(spec[k] / spec[mask].max()), k


def tone(n, f, amp, phase=0.0, noise=0.0, seed=1):
    rng = np.random.default_rng(seed)
    t = np.arange(n)
    x = amp * 32767 * np.cos(2 * math.pi * f * t + phase) + noise * 32767 * rng.standard_normal(n)
    return [int(v) for v in np.clip(np.round(x), -32768, 32767)]


def main(build, vvp):
    lut = gen_lut(f"{build}/sine_quarter.hex")
    print("DDC checks (N=4 stage CIC, R=16, 16-bit datapath)")

    # 1. bit-exact against the integer model, with random input gaps
    rng = np.random.default_rng(7)
    x = [int(v) for v in rng.integers(-32768, 32768, 20000)]
    inc = 0x1234_5679
    i_r, q_r, _, _ = run(vvp, build, x, inc, gap=25, tag="exact")
    i_m, q_m = model(x, inc, lut)
    n = min(len(i_r), len(i_m))
    bad = sum((i_r[:n] != np.array(i_m[:n])) | (q_r[:n] != np.array(q_m[:n])))
    check("bit-exact vs integer model", n == len(i_m) and bad == 0,
          f"{n} I/Q output samples, {bad} mismatches (random input, 25% input gaps)")

    # 2. NCO spectral purity from the RTL's own NCO output
    nfft = 1 << 14
    inc = int(round(0.1234567 * 2 ** 32))
    _, _, c, s = run(vvp, build, [0] * nfft, inc, tag="nco")
    sf, _ = sfdr_db(c[:nfft] + 1j * s[:nfft])
    check("NCO SFDR", sf > 70.0, f"{sf:.1f} dBc at f = 0.1234567 fs (12-bit phase -> theory ~72 dBc)")

    # 3. receiver: tone at f_nco + d -> complex tone at +d after decimation
    f_nco, d = 0.2, 0.01
    inc = int(round(f_nco * 2 ** 32))
    x = tone(R * 4096 + 64, f_nco + d, 0.8, noise=1e-4)
    i_r, q_r, _, _ = run(vvp, build, x, inc, tag="rx")
    y = (i_r + 1j * q_r)[32:32 + 4096]
    sf, k = sfdr_db(y)
    f_out = k / len(y) if k < len(y) // 2 else k / len(y) - 1
    exp_f = d * R
    amp = np.abs(np.fft.fft(y * np.blackman(len(y))))[k] / np.sum(np.blackman(len(y))) / 32767
    check("receiver tone position", abs(f_out - exp_f) < 2 / len(y),
          f"output tone at {f_out:+.4f} fs_out, expected {exp_f:+.4f} (input at f_nco + {d} fs)")
    check("receiver SFDR", sf > 60.0, f"{sf:.1f} dBc in the decimated output")
    # a real tone of amplitude A becomes A/2 after x*e^-jwn, then CIC droop at offset d
    droop = abs(math.sin(math.pi * d * R) / (R * math.sin(math.pi * d))) ** N_STAGES
    exp_amp = 0.8 / 2 * droop
    check("receiver gain", abs(amp - exp_amp) / exp_amp < 0.02,
          f"output amplitude {amp:.4f} FS, expected {exp_amp:.4f} (0.8/2 x CIC droop {20 * math.log10(droop):.2f} dB)")

    # 4. CIC magnitude response vs theory (NCO at DC, I path only)
    print("    f_in/fs_in   measured dB   theory dB")
    worst = 0.0
    for f in (0.001, 0.01, 0.02, 0.03, 0.045):
        x = tone(R * 2048 + 64, f, 0.9)
        i_r, _, _, _ = run(vvp, build, x, 0, tag="cic")
        y = i_r[16:16 + 2048].astype(float)
        meas = np.sqrt(2 * np.mean((y - y.mean()) ** 2)) / (0.9 * 32767 * (lut[1023] / 32768))
        th = abs(math.sin(math.pi * f * R) / (R * math.sin(math.pi * f))) ** N_STAGES
        md, td = 20 * math.log10(meas), 20 * math.log10(th)
        worst = max(worst, abs(md - td))
        print(f"    {f:9.3f}   {md:11.2f}   {td:9.2f}")
    check("CIC response vs theory", worst < 0.3, f"worst deviation {worst:.3f} dB over 5 frequencies")

    print("TEST PASSED" if not FAILS else f"TEST FAILED: {FAILS}")
    sys.exit(1 if FAILS else 0)


if __name__ == "__main__":
    main(sys.argv[1], sys.argv[2])
