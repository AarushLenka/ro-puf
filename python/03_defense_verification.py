# Runs the identical attack from Part 7 against both datasets and compares.

import numpy as np
import pandas as pd
from sklearn.linear_model import LogisticRegression
from sklearn.model_selection import train_test_split
from sklearn.metrics import accuracy_score
import matplotlib.pyplot as plt

def load_and_prepare(csv_path: str):
    df = pd.read_csv(csv_path)
    X = np.array([[(c >> (7 - i)) & 1 for i in range(8)] for c in df['challenge']])
    y = np.array([[(r >> b) & 1 for b in range(8)] for r in df['response']])
    return X, y

def run_attack(X, y, n_train: int) -> float:
    X_train, X_test, y_train, y_test = train_test_split(X, y, train_size=n_train, random_state=42)
    accs = []
    for bit in range(8):
        m = LogisticRegression(max_iter=1000)
        m.fit(X_train, y_train[:, bit])
        accs.append(accuracy_score(y_test[:, bit], m.predict(X_test)))
    return float(np.mean(accs))

X_naive,    y_naive    = load_and_prepare('data/crp_dataset.csv')
X_hardened, y_hardened = load_and_prepare('data/crp_dataset_hardened.csv')

training_sizes = [20, 40, 80, 120, 160, 200]
acc_naive    = [run_attack(X_naive,    y_naive,    n) for n in training_sizes]
acc_hardened = [run_attack(X_hardened, y_hardened, n) for n in training_sizes]

print(f"{'CRPs':>6} | {'Naive PUF':>10} | {'Hardened PUF':>13}")
print("-" * 36)
for n, a, h in zip(training_sizes, acc_naive, acc_hardened):
    print(f"{n:>6} | {a*100:>9.1f}% | {h*100:>12.1f}%")

plt.figure(figsize=(9, 5))
plt.plot(training_sizes, [a*100 for a in acc_naive],    'r-o', label='Naive PUF (no defense)')
plt.plot(training_sizes, [a*100 for a in acc_hardened], 'g-o', label='Hardened PUF (XOR mixing)')
plt.axhline(50, color='gray', linestyle='--', label='Random-chance baseline')
plt.xlabel('Training CRPs available to attacker'); plt.ylabel('Attack accuracy (%)')
plt.title('ML Modeling Attack: Naive vs Hardened PUF')
plt.legend(); plt.grid(True); plt.tight_layout()
plt.savefig('plots/defense_comparison.png', dpi=150)
plt.show()
print("\nSaved plots/defense_comparison.png")
