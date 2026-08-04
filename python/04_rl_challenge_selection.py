# Q-learning agent that discovers which challenges give the most reliable,
# highest-entropy responses. Trains against a simulator seeded from your
# real crp_dataset.csv so it reflects your actual board's behavior.

import numpy as np
import pandas as pd
import matplotlib.pyplot as plt
import json
import os

os.makedirs('plots',  exist_ok=True)
os.makedirs('models', exist_ok=True)

# ── Step 1: build a noise-accurate simulator from your real data ─────────
df = pd.read_csv('data/crp_dataset.csv')
crp_lookup = {
    int(row['challenge']): {'response': int(row['response']), 'stability': float(row['stability'])}
    for _, row in df.iterrows()
}

def query_puf_simulated(challenge: int) -> int:
    """
    One simulated noisy query. Uses the real per-challenge stability score
    from your hardware: if stability = 0.857 (6 of 7 trials matched), each
    bit independently has a ~14.3% chance of flipping in this draw.
    """
    info = crp_lookup[challenge]
    flip_prob = 1.0 - info['stability']
    noisy = 0
    for bit in range(8):
        original = (info['response'] >> bit) & 1
        actual = (1 - original) if (np.random.random() < flip_prob) else original
        noisy |= (actual << bit)
    return noisy

# ── Step 2: reward function ───────────────────────────────────────────────
def entropy_score(response: int) -> float:
    """1.0 if exactly 4 of 8 bits are 1 (perfectly balanced), 0.0 if all-0 or all-1."""
    ones = bin(response).count('1')
    return 1.0 - abs(ones - 4) / 4.0

def get_reward(challenge: int, n_samples: int = 7):
    """
    Query the challenge n_samples times, majority-vote to find the stable
    response, then combine stability and entropy into one reward.
    Stability is weighted higher: an unstable CRP is useless even with
    perfect entropy, since authentication would fail unpredictably.
    """
    responses = [query_puf_simulated(challenge) for _ in range(n_samples)]
    stable = 0
    for bit in range(8):
        ones = sum(1 for r in responses if (r >> bit) & 1)
        if ones > n_samples // 2:
            stable |= (1 << bit)
    stability = sum(1 for r in responses if r == stable) / n_samples
    entropy   = entropy_score(stable)
    reward    = 0.6 * stability + 0.4 * entropy
    return reward, stability, entropy, stable

# ── Step 3: Q-learning agent ──────────────────────────────────────────────
# Q[a] holds this agent's current estimate of "how good is challenge a".
# At each step: with probability epsilon, try a random challenge (explore).
# Otherwise, pick whichever challenge currently has the highest Q (exploit).
# After seeing the reward: Q[a] += alpha * (reward - Q[a])   (a simple running average)

class QLearningChallengeSelector:
    def __init__(self, n_challenges=256, alpha=0.1, epsilon=0.3):
        self.n = n_challenges
        self.alpha = alpha
        self.epsilon = epsilon
        self.Q = np.full(n_challenges, 0.5)              # neutral starting estimate
        self.visit_count = np.zeros(n_challenges, dtype=int)

    def select_action(self) -> int:
        if np.random.random() < self.epsilon:
            return np.random.randint(self.n)
        return int(np.argmax(self.Q))

    def update(self, action: int, reward: float):
        self.Q[action] += self.alpha * (reward - self.Q[action])
        self.visit_count[action] += 1

    def get_top_k(self, k: int = 8) -> list:
        return np.argsort(self.Q)[::-1][:k].tolist()

# ── Step 4: train ──────────────────────────────────────────────────────────
N_EPISODES = 2000
agent = QLearningChallengeSelector(alpha=0.1, epsilon=0.3)
rewards_log = []

print("Training Q-learning agent...")
for episode in range(N_EPISODES):
    agent.epsilon = max(0.05, 0.3 * (1 - episode / N_EPISODES))  # explore less as it learns
    action = agent.select_action()
    reward, stability, entropy, _ = get_reward(action)
    agent.update(action, reward)
    rewards_log.append(reward)

    if episode % 200 == 0:
        avg_r = np.mean(rewards_log[-200:]) if episode > 0 else reward
        print(f"Episode {episode:4d} | avg reward {avg_r:.3f} | epsilon {agent.epsilon:.3f} | top-4 {agent.get_top_k(4)}")

print("\nTraining complete.")

# ── Step 5: evaluate RL-selected vs random challenges ──────────────────────
top_8 = agent.get_top_k(8)
random_8 = np.random.choice(256, 8, replace=False).tolist()
print(f"\nRL-selected challenges: {top_8}")

def evaluate_set(challenges: list, n_eval: int = 50) -> dict:
    stabilities, entropies = [], []
    for c in challenges:
        for _ in range(n_eval // len(challenges)):
            _, stab, ent, _ = get_reward(c)
            stabilities.append(stab); entropies.append(ent)
    return {
        'avg_stability': np.mean(stabilities),
        'avg_entropy':   np.mean(entropies),
        'combined':      0.6*np.mean(stabilities) + 0.4*np.mean(entropies)
    }

rl_eval, rnd_eval = evaluate_set(top_8), evaluate_set(random_8)
print(f"RL-selected:  stability={rl_eval['avg_stability']:.3f}  entropy={rl_eval['avg_entropy']:.3f}  combined={rl_eval['combined']:.3f}")
print(f"Random:       stability={rnd_eval['avg_stability']:.3f}  entropy={rnd_eval['avg_entropy']:.3f}  combined={rnd_eval['combined']:.3f}")

# ── Step 6: plots ────────────────────────────────────────────────────────
fig, axes = plt.subplots(1, 3, figsize=(15, 4))

q_grid = agent.Q.reshape(16, 16)
im = axes[0].imshow(q_grid, cmap='RdYlGn', vmin=0, vmax=1)
axes[0].set_title('Learned Q-values'); axes[0].set_xlabel('C[3:0]'); axes[0].set_ylabel('C[7:4]')
plt.colorbar(im, ax=axes[0])
for c in top_8:
    axes[0].plot(c & 0xF, (c >> 4) & 0xF, 'b*', markersize=12)

window = 50
smoothed = [np.mean(rewards_log[max(0, i-window):i+1]) for i in range(len(rewards_log))]
axes[1].plot(smoothed, 'b-'); axes[1].set_xlabel('Episode'); axes[1].set_ylabel('Reward (smoothed)')
axes[1].set_title('Reward over training'); axes[1].grid(True)

vc_grid = agent.visit_count.reshape(16, 16)
im2 = axes[2].imshow(vc_grid, cmap='Blues')
axes[2].set_title('Times each challenge was queried'); axes[2].set_xlabel('C[3:0]'); axes[2].set_ylabel('C[7:4]')
plt.colorbar(im2, ax=axes[2])

plt.tight_layout()
plt.savefig('plots/rl_challenge_selection.png', dpi=150)
plt.show()

with open('models/rl_selected_challenges.json', 'w') as f:
    json.dump({'challenges': top_8, 'q_values': agent.Q[top_8].tolist()}, f, indent=2)

print("\nSaved models/rl_selected_challenges.json")


# ── Optional: DQN variant ────────────────────────────────────────────────
# Only worth using if your challenge space grows beyond a few thousand.
# For 256 challenges, the Q-learning agent above is simpler and just as effective.

try:
    import torch
    import torch.nn as nn
    import torch.optim as optim
    from collections import deque
    import random as pyrandom

    class QNetwork(nn.Module):
        """Maps a one-hot challenge encoding to an estimated Q-value per challenge."""
        def __init__(self, n_challenges=256):
            super().__init__()
            self.net = nn.Sequential(
                nn.Linear(n_challenges, 128), nn.ReLU(),
                nn.Linear(128, 64),  nn.ReLU(),
                nn.Linear(64, n_challenges)
            )
        def forward(self, x):
            return self.net(x)

    class DQNAgent:
        def __init__(self, n_challenges=256, lr=1e-3, epsilon=0.3):
            self.n = n_challenges
            self.epsilon = epsilon
            self.policy_net = QNetwork(n_challenges)
            self.optimizer = optim.Adam(self.policy_net.parameters(), lr=lr)
            self.memory = deque(maxlen=10000)

        def select_action(self) -> int:
            if pyrandom.random() < self.epsilon:
                return pyrandom.randint(0, self.n - 1)
            with torch.no_grad():
                q = self.policy_net(torch.ones(self.n))
                return int(q.argmax().item())

        def remember(self, action: int, reward: float):
            self.memory.append((action, reward))

        def train_step(self, batch_size=32):
            if len(self.memory) < batch_size:
                return
            batch = pyrandom.sample(self.memory, batch_size)
            actions = torch.tensor([b[0] for b in batch], dtype=torch.long)
            rewards = torch.tensor([b[1] for b in batch], dtype=torch.float32)
            q_vals = self.policy_net(torch.ones(batch_size, self.n))
            q_taken = q_vals.gather(1, actions.unsqueeze(1)).squeeze()
            loss = nn.MSELoss()(q_taken, rewards)
            self.optimizer.zero_grad(); loss.backward(); self.optimizer.step()

        def get_top_k(self, k=8) -> list:
            with torch.no_grad():
                q = self.policy_net(torch.ones(self.n))
                return q.topk(k).indices.tolist()

    dqn_agent = DQNAgent(n_challenges=256, epsilon=0.3)
    print("\nTraining DQN agent...")
    for episode in range(2000):
        dqn_agent.epsilon = max(0.05, 0.3 * (1 - episode / 2000))
        action = dqn_agent.select_action()
        reward, _, _, _ = get_reward(action)
        dqn_agent.remember(action, reward)
        dqn_agent.train_step()
        if episode % 400 == 0 and episode > 0:
            print(f"Episode {episode}: top-4 = {dqn_agent.get_top_k(4)}")

    print(f"\nDQN top 8 challenges: {dqn_agent.get_top_k(8)}")
    torch.save(dqn_agent.policy_net.state_dict(), 'models/dqn_policy.pt')

except ImportError:
    print("\nTorch not installed — skipping DQN variant. Run: pip install torch")
