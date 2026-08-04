# Sweeps all 256 challenges against the PUF, using majority voting to filter
# out measurement noise, and saves the results to a CSV.

from pynq import Overlay
import time
import csv
import os

# ── Load the bitstream ────────────────────────────────────────────────────
overlay = Overlay("puf_bd_wrapper.bit")

gpio_out = overlay.axi_gpio_0.channel1   # 9-bit: challenge[7:0] + start[8]
gpio_in  = overlay.axi_gpio_1.channel1   # 9-bit: response[7:0] + done[8]

NUM_TRIALS  = 7       # odd number → majority vote always has a definite winner
WINDOW_WAIT = 0.001    # 1 ms is far more than the ~0.4 microsecond measurement takes

def query_puf(challenge: int) -> int:
    """Send one challenge, wait for the done flag, return the 8-bit response."""
    gpio_out.write(challenge | (1 << 8), 0x1FF)   # set challenge bits + start bit
    time.sleep(WINDOW_WAIT)

    for _ in range(100):                            # poll for done, with a timeout
        if gpio_in.read() & (1 << 8):
            break
        time.sleep(0.0001)

    gpio_out.write(challenge, 0x1FF)                # clear the start bit
    return gpio_in.read() & 0xFF

def majority_vote(responses: list) -> tuple:
    """
    For each of the 8 bit positions, take whichever value (0 or 1) appeared
    in more than half the trials. Returns (stable_response, stability_score),
    where stability_score is the fraction of trials that exactly matched the
    stable response — a rough measure of how noisy this particular CRP is.
    """
    stable = 0
    for bit in range(8):
        ones = sum(1 for r in responses if (r >> bit) & 1)
        if ones > NUM_TRIALS // 2:
            stable |= (1 << bit)
    stability = sum(1 for r in responses if r == stable) / NUM_TRIALS
    return stable, stability

print("Collecting CRPs...")
crp_data = []

for challenge in range(256):
    raw = [query_puf(challenge) for _ in range(NUM_TRIALS)]
    stable, stability = majority_vote(raw)
    crp_data.append({
        'challenge':  challenge,
        'response':   stable,
        'stability':  round(stability, 3),
        'raw_trials': str(raw)
    })
    if challenge % 32 == 0:
        print(f"  {challenge}/256")

os.makedirs('data', exist_ok=True)
with open('data/crp_dataset.csv', 'w', newline='') as f:
    writer = csv.DictWriter(f, fieldnames=['challenge', 'response', 'stability', 'raw_trials'])
    writer.writeheader()
    writer.writerows(crp_data)

print(f"Saved {len(crp_data)} CRPs to data/crp_dataset.csv")

# ── Sanity check ─────────────────────────────────────────────────────────
stable_count  = sum(1 for c in crp_data if c['stability'] >= 6/7)
avg_stability = sum(c['stability'] for c in crp_data) / len(crp_data)
avg_ones      = sum(bin(c['response']).count('1') for c in crp_data) / len(crp_data)

print(f"\nStable CRPs (>= 6/7 trials matching): {stable_count}/256")
print(f"Average stability: {avg_stability:.3f}")
print(f"Average ones per response byte: {avg_ones:.2f} (ideal is 4.0)")
print("If stable CRPs < 200, or avg ones is far from 4.0, see Part 12 (Troubleshooting).")