using System;

namespace Pawductivity
{
    // Pure rules, independent of rendering and input.
    public sealed class ShiftState
    {
        public const float Duration = 40f;
        public const float ScratchDelay = 5f;
        public float Elapsed { get; private set; }
        public int Quota { get; private set; }
        public int Damage { get; private set; }
        public bool Finished { get; private set; }
        public bool Won { get; private set; }
        public bool CatActive { get; private set; }
        public float CatRemaining { get; private set; }
        public float NextCat { get; private set; } = 4f;
        public event Action CatSpawned;
        public event Action<bool> CatRemoved;
        public event Action Ended;
        private readonly Random random;

        public ShiftState(int seed) { random = new Random(seed); }

        public void Work()
        {
            if (!Finished) Quota = Math.Min(100, Quota + 5);
        }

        public bool Shoo(bool visible)
        {
            if (Finished || !CatActive || !visible) return false;
            RemoveCat(false);
            return true;
        }

        public void Tick(float delta)
        {
            if (Finished || delta <= 0) return;
            // Integrate chronological deadlines even after a slow frame.
            float remaining = Math.Min(delta, Duration - Elapsed);
            while (remaining > 0 && !Finished)
            {
                float deadline = CatActive ? CatRemaining : NextCat;
                float step = Math.Min(remaining, deadline);
                Elapsed += step;
                remaining -= step;
                if (CatActive) CatRemaining -= step; else NextCat -= step;
                if (Elapsed >= Duration - .0001f) { Elapsed = Duration; Finish(); break; }
                if (CatActive && CatRemaining <= 0)
                {
                    Damage = Math.Min(50, Damage + 10);
                    RemoveCat(true);
                    if (Damage >= 50) Finish();
                }
                else if (!CatActive && NextCat <= 0)
                {
                    CatActive = true;
                    CatRemaining = ScratchDelay;
                    CatSpawned?.Invoke();
                }
            }
        }

        private void RemoveCat(bool scratched)
        {
            CatActive = false;
            CatRemaining = 0;
            NextCat = 5f + (float)random.NextDouble() * 4f;
            CatRemoved?.Invoke(scratched);
        }

        private void Finish()
        {
            Finished = true;
            Won = Quota >= 100 && Damage < 50;
            Ended?.Invoke();
        }
    }
}
