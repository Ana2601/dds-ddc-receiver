# DDS / NCO and digital down-converter (SDR receiver front end)

[![CI](https://github.com/Ana2601/dds-ddc-receiver/actions/workflows/ci.yml/badge.svg)](https://github.com/Ana2601/dds-ddc-receiver/actions/workflows/ci.yml)

The signal-processing front end of a software-defined radio: an NCO (direct digital synthesis), a quadrature mixer and CIC decimation filters, verified bit-exactly and spectrally.

## Chain

```
ADC samples ──►(×)──► CIC ↓16 ──► I
               │
          NCO cos/sin (32-bit phase accumulator, 1024-entry quarter-wave ROM)
               │
            ──►(×)──► CIC ↓16 ──► Q
```

- `rtl/nco.sv`: 32-bit phase accumulator, 12-bit phase → 16-bit amplitude via quarter-wave symmetry; f_out = inc / 2³² · f_s
- `rtl/ddc.sv`: multiply by e^(−jωn) (I = x·cos, Q = −x·sin), Q1.15 rounding
- `rtl/cic_decimator.sv`: N = 4 stages, R = 16, Hogenauer structure; integrator wrap-around is exact by design, gain normalised to 1

## Verification (`scripts/run_checks.py`)

1. **Bit-exact**: an integer Python model of the full chain (NCO, rounding, wrap-around CIC) must match every RTL output sample, with random inputs and 25 % random input gaps.
2. **NCO spectral purity**: SFDR measured on the RTL's own cos/sin output (coherent FFT, Blackman window).
3. **Receiver**: a tone at f_NCO + 0.01·f_s must appear as a complex tone at exactly +0.16·f_out, with the expected gain.
4. **CIC response**: the measured RTL gain at 5 frequencies must match the theoretical |sin(πfR)/(R·sin(πf))|⁴.

## Results (measured)

| Check | Result |
|---|---|
| Bit-exact vs. model | **1,250 / 1,250 I/Q samples, 0 mismatches** |
| NCO SFDR | **72.0 dBc** (theory for a 12-bit phase ≈ 72 dBc) |
| Receiver tone position | +0.1600 f_out (expected +0.1600) |
| Receiver SFDR | **75.9 dBc** |
| Receiver gain | 0.3353 FS vs. 0.3377 expected (0.8/2 × −1.47 dB CIC droop) |
| CIC response vs. theory | worst deviation **0.017 dB** (0 to −37.3 dB) |

| f_in / f_s | Measured | Theory |
|---|---|---|
| 0.001 | −0.02 dB | −0.01 dB |
| 0.010 | −1.47 dB | −1.47 dB |
| 0.020 | −6.04 dB | −6.04 dB |
| 0.030 | −14.27 dB | −14.29 dB |
| 0.045 | −37.30 dB | −37.30 dB |

## Run

```bash
make test
make lint
make synth     # CIC cell count
```

## Limitations / next steps

No CIC droop-compensation FIR or half-band stage after the CIC, and no phase dithering in the NCO (which would trade the 72 dBc spurs for a noise floor).

## Setup

- [OSS CAD Suite](https://github.com/YosysHQ/oss-cad-suite-build) (Icarus Verilog, Verilator, Yosys)
- Python packages: `pip install -r requirements.txt`

```bash
make test
make lint
```

The same commands run in CI on every push (`.github/workflows/ci.yml`).
