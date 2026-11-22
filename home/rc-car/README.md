# RC car

Home-built RC car driven from a FrSky Taranis X-Lite (S/Pro) running OpenTX 2.3, configured
with OpenTX Companion (`companion23`).

**Active work:** none. The car model is set up and was verified on the bench on 2026-11-22
(see "Checks before the first run"). Still open: take a backup of the final configuration
(see "Backups"). History is in
[`changelog.md`](changelog.md).

## Hardware

| Part | Model | Notes |
|---|---|---|
| Radio | FrSky Taranis X-Lite (S/Pro), OpenTX 2.3 | Internal ISRM module (ACCESS) |
| Receiver | FrSky Archer Plus R6 | ACCESS. Pin *n* = CH *n* by default. 3.5–10 V |
| ESC | Hobbywing Quicrun WP 10BL120 | Brushless, 120 A. BEC set to **6 V** (verified: RxBt = 6.1 V). Powers the receiver and servo. No telemetry output |
| Steering servo | — | Receiver pin 1 |

## Control layout

![X-Lite switch layout](X-Lite%20switch%20layout.jpg)

- **Left stick, vertical → throttle** (CH2, ESC on receiver pin 2).
- **Right stick, horizontal → steering** (CH1, servo on receiver pin 1).
- **SA → safety switch**: **down (pushed away from you) = safe**, which forces the throttle to
  neutral. Up (toward you) = armed.

Companion names the sticks after airplane controls, and which physical stick is which depends
on the stick mode (**Radio Settings → Stick mode**):

| Mode | Left stick, vertical | Right stick, horizontal |
|---|---|---|
| Mode 2 | `Thr` | `Ail` |
| Mode 1 | `Ele` | `Ail` |

This radio is in **Mode 2**, which the configuration below assumes. In Mode 1, use `Ele`
instead of `Thr` as the throttle source.

## Backups

`backups/` holds `.otx` exports of the radio's models and settings, read with Companion.

- `backups/backup-22.11.2026.otx` — taken before the car model was created. It contains the
  radio settings and 3 models (`model1`–`model3`).

To take a new backup: turn the radio on with USB connected, choose **USB Storage (SD)**, then
use **Read Models and Settings from Radio** in Companion and save the file as
`backups/backup-<dd.mm.yyyy>.otx`.

## Model configuration (Companion)

Create the model in an empty slot so the existing models stay untouched.

**Setup tab**
- Internal module: **ACCESS**, channels CH1–8, Receiver 1.
- Throttle warning: **off**. Neutral is mid-stick, so the "throttle at the bottom" check
  would always fire. The SA safety switch replaces it.
- Throttle trim idle only: **off**.
- Failsafe: **Custom**, CH1 = 0, CH2 = 0. On ACCESS, this is stored in the receiver.

**Inputs tab**
- `I1 Steer`: source `Ail`, weight 100. The first version of the model had the wrong source
  here (a stick mix-up, something like `Ail`/`Ele`), which put steering on the left stick.
  Fixed in the model's config. Optional 20–30% expo for softer steering near the center.
- `I2 Thr`: source `Thr`, weight 100.

**Mixes tab**
- CH1 ← `I1 Steer`, 100%.
- CH2 ← `I2 Thr`, 100%.

**Outputs tab**
- CH1: tick **Invert** if the steering is backwards. Use **Subtrim** to make the car drive
  straight, and lower **Min/Max** if the servo buzzes or binds at full lock.
- CH2: leave it alone. The ESC learns its direction and range during calibration.

**Special Functions**
- `SF1: SA (safe position) → Override CH2, value 0`. On this radio, safe = SA down, pushed
  away from you. **The value must be 0, not -100**: on a car ESC, -100 is full brake or full
  reverse.

**Telemetry**

Sensors can only be discovered on the radio, with the receiver bound and powered (TELEMETRY
page → Discover new sensors). Discovered on 2026-11-22:

| # | Sensor | Reading | Meaning |
|---|---|---|---|
| 1 | RSSI | 100 | Signal strength. Default alarms: low 45, critical 42 |
| 2 | A2 | 0 V | Receiver analog input. Nothing is connected to it |
| 3 | RxBt | 6.1 V | Receiver supply, which is the ESC's BEC voltage |
| 4 | VFR | 100 % | Share of valid frames received |

Low-BEC alarm (to do):
- Logical Switch `L1: a<x RxBt 5.5V`, Duration 2 s.
- `SF2: L1 → Play Value RxBt, repeat 10s`. Optionally `SF3: L1 → Haptic`.
- Telemetry Screen 1: Values, showing `RSSI`, `RxBt`, `VFR`.

There's no main battery voltage, because the ESC sends no telemetry. RxBt stays at about 6 V
until the pack is nearly empty, so the ESC's low-voltage cutoff is what protects the LiPo.

Before writing to the radio, check the model in Companion's **Simulator**: steering moves CH1
only, throttle moves CH2 only, and SA holds CH2 at 0. Then use **Write Models and Settings to
Radio**.

## Registering and binding the receiver (on the radio)

1. **Register (once per receiver).** Model Setup → Internal RF → **[Register]**. Hold the
   receiver's **F/S button** while you power it on. When its name appears on the radio, select
   it and confirm. Then unpower the receiver.
2. **Bind.** Receiver 1 → **[Bind]**. Power the receiver on without pressing the button, pick
   it from the list, then power-cycle the receiver.

If registration fails, check that the receiver is running ACCESS firmware and not ACCST D16.
Archer Plus receivers can be flashed with either.

## ESC throttle calibration

Do this after the model is set up and bound, **with the wheels off the ground**. This is the
usual Hobbywing Quicrun procedure; check it against the ESC manual.

1. Turn the radio on and put the throttle stick at **mid-travel** (neutral).
2. Hold **SET**, switch the ESC on, and release SET when the red LED starts flashing.
3. Neutral: press SET. The green LED flashes once.
4. Full forward (stick up): press SET. Green flashes twice.
5. Full reverse/brake (stick down): press SET. Green flashes three times.
6. The motor becomes active after about 3 seconds.

Run the calibration again after any change to CH2: direction, limits or trim.

**Running mode:** in forward/brake/reverse mode, reverse needs a double push: stick down to
brake, back to neutral, then down again.

**BEC voltage:** only choose 7.4 V if the steering servo is rated for it.

## Checks before the first run

With the wheels off the ground. All passed on 2026-11-22, after the ESC calibration:

- [x] Steering goes the right way and the car tracks straight (subtrim).
- [x] Throttle up = forward, down = brake/reverse.
- [x] SA down (safe) keeps the motor stopped whatever the throttle stick does.
- [x] Failsafe: turn the radio off with throttle applied. The motor must stop.

## Hard-won lessons

- Double-check each input's stick source in the Simulator or Channel Monitor before writing the
  model. A mixed-up source (`Ail`/`Ele`/`Rud`) put steering on the left stick here.
- Check in the Channel Monitor which receiver pin each device is on. With the ESC and servo
  swapped, the SA override and the failsafe protected the servo instead of the motor.

- In OpenTX, a channel at **0** is neutral (1500 µs) for a car ESC. **-100** is full brake or
  reverse, so never use -100 for a throttle cut or failsafe on the car.
- On Mode 2, the left vertical axis usually has no centering spring, so neutral is wherever you
  leave the stick at mid-travel. It's worth checking whether the gimbal can be made
  self-centering on that axis.
- To run Companion in English on this French system:
  `env LC_ALL=C.UTF-8 LANGUAGE=en companion23`. No `en_*` locale is installed, but `C.UTF-8`
  is enough. You can also set it permanently in **Paramètres → Paramètres de l'application →
  Langue**.
