# Trains one logistic regression model per response bit and measures how
# accurately it predicts responses it never trained on.

import numpy as np
import pandas as pd
from sklearn.linear_model import LogisticRegression
from sklearn.model_selection import train_test_split
from sklearn.metrics import accuracy_score
import matplotlib.pyplot as plt
import os

os.makedirs('models', exist_ok=True)
os.makedirs('plots',  exist_ok=True)

# ── Load data ────────────────────────────────────────────────────────────
df = pd.read_csv('data/crp_dataset.csv')
print(f"Loaded {len(df)} CRPs.")

def int_to_bits(value: int, n_bits: int = 8) -> list:
    """8-bit integer -> list of 8 individual bits (MSB first)."""
    return [(value >> (n_bits - 1 - i)) & 1 for i in range(n_bits)]

# X: one row per challenge, 8 columns (the bit-expanded challenge)
X = np.array([int_to_bits(c) for c in df['challenge']])
# y: one row per challenge, 8 columns (the 8 response bits)
y = np.array([[(r >> bit) & 1 for bit in range(8)] for r in df['response']])

print(f"Feature matrix: {X.shape}, label matrix: {y.shape}")

# ── Attack at increasing training-set sizes ─────────────────────────────
training_sizes = [20, 40, 80, 120, 160, 200]
results = []

for n_train in training_sizes:
    X_train, X_test, y_train, y_test = train_test_split(
        X, y, train_size=n_train, random_state=42
    )

    models = []
    for bit in range(8):
        m = LogisticRegression(max_iter=1000)
        m.fit(X_train, y_train[:, bit])
        models.append(m)

    per_bit_acc = [
        accuracy_score(y_test[:, bit], models[bit].predict(X_test))
        for bit in range(8)
    ]

    # Stricter metric: the FULL 8-bit response must be right for it to count.
    y_pred_full = np.column_stack([m.predict(X_test) for m in models])
    full_response_acc = np.mean(np.all(y_pred_full == y_test, axis=1))

    results.append({
        'n_train': n_train,
        'avg_bit_acc': np.mean(per_bit_acc),
        'full_response_acc': full_response_acc
    })
    print(f"n_train={n_train:3d}  bit-acc={np.mean(per_bit_acc):.3f}  full-response-acc={full_response_acc:.3f}")

# ── Plot ─────────────────────────────────────────────────────────────────
results_df = pd.DataFrame(results)
fig, axes = plt.subplots(1, 2, figsize=(12, 5))

axes[0].plot(results_df['n_train'], results_df['avg_bit_acc'] * 100, 'b-o')
axes[0].axhline(90, color='r', linestyle='--', label='90% threshold')
axes[0].set_xlabel('Training CRPs'); axes[0].set_ylabel('Accuracy (%)')
axes[0].set_title('Bit-level accuracy vs training size'); axes[0].legend(); axes[0].grid(True)

axes[1].plot(results_df['n_train'], results_df['full_response_acc'] * 100, 'g-o')
axes[1].axhline(50, color='r', linestyle='--', label='50% threshold')
axes[1].set_xlabel('Training CRPs'); axes[1].set_ylabel('Accuracy (%)')
axes[1].set_title('Full 8-bit response accuracy vs training size'); axes[1].legend(); axes[1].grid(True)

plt.tight_layout()
plt.savefig('plots/ml_attack_naive_puf.png', dpi=150)
plt.show()

print("\nSaved plots/ml_attack_naive_puf.png")
print("With ~120 CRPs, bit accuracy typically exceeds 85%, meaning an attacker")
print("can predict most response bits without ever touching the hardware.")
