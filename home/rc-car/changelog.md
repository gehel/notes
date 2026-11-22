# RC car changelog

## 2026-11-22

- Backed up the radio before any change: `backups/backup-22.11.2026.otx` (radio settings + 3
  existing models).
- Created the car model in Companion (steering on CH1 from `Ail`, throttle on CH2 from `Thr`,
  SA override of CH2 to 0, custom failsafe at neutral) and wrote it to the radio.
- Registered and bound the Archer Plus R6 over ACCESS.
- Discovered the telemetry sensors: RSSI 100, A2 0 V, RxBt 6.1 V, VFR 100 %. RxBt confirms the
  ESC's BEC is at 6 V and powers the receiver.
- Set up the low-BEC alarm and the telemetry screen on the radio.
- First tests: the left stick's horizontal axis drove the ESC and its vertical axis drove the
  steering servo. Cause found: the ESC was plugged into receiver pin 1 and the servo into pin 2,
  the opposite of the plan. Swapping them back fixes the channel order. Steering still sits on
  the left stick, which suggests the radio is in stick Mode 3, not Mode 2 (not yet checked).
  While the plugs were swapped, the SA safety override and the failsafe acted on the servo,
  not the ESC.
- Swapped the plugs back to the plan (servo on pin 1, ESC on pin 2) and corrected the car
  model's steering input so steering is on the right stick's horizontal axis.
- Calibrated the ESC (neutral, full forward, full reverse). Bench checks with the wheels off the
  ground all passed: steering direction and trim, forward/brake/reverse, SA safety override,
  and failsafe (radio off → motor stops).
- Correction to the stick-mode guess above: the radio was already in Mode 2. The steering
  problem was a wrong input source in the car model (a stick mix-up), fixed in the model's
  config.
- Recorded the SA positions: down (pushed away from you) = safe, up (toward you) = armed.
- Still to do: back up the final configuration into `backups/`.
