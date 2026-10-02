using System;
using System.Collections.Generic;
using UnityEngine;

namespace Pawductivity
{
    public sealed class PawductivityGame : MonoBehaviour
    {
        private ShiftState shift;
        private Camera view;
        private Transform cat, paw, tail;
        private Renderer wallpaper, screen;
        private GameObject room;
        private AudioSource speaker;
        private AudioClip workSound, meowSound, spraySound, scratchSound;
        private readonly List<Material> materials = new List<Material>();
        private float yaw, pitch, sprayFlash, workFlash;
        private bool started, paused;
        private string status = "Твой офис. Твои коты. Твоя выдержка.";
        private GUIStyle titleStyle, textStyle, smallStyle, numberStyle;
        private Texture2D intact, scratched, critical;
        private readonly Color ink = new Color(.12f, .19f, .23f);
        private readonly Color mint = new Color(.37f, .83f, .69f);
        private readonly Color coral = new Color(1f, .46f, .35f);

        private void Awake()
        {
            Application.targetFrameRate = 60;
            intact = Resources.Load<Texture2D>("Wallpaper/wallpaper_intact");
            scratched = Resources.Load<Texture2D>("Wallpaper/wallpaper_scratched");
            critical = Resources.Load<Texture2D>("Wallpaper/wallpaper_critical");
            BuildRoom();
            speaker = gameObject.AddComponent<AudioSource>();
            speaker.playOnAwake = false;
            workSound = Tone(680, .08f, 0);
            meowSound = Tone(490, .35f, 1);
            spraySound = Tone(1200, .3f, 2);
            scratchSound = Tone(150, .2f, 2);
            ResetShift();
            Unlock();
        }

        private void ResetShift()
        {
            if (cat != null) Destroy(cat.gameObject);
            cat = null;
            shift = new ShiftState(Environment.TickCount);
            shift.CatSpawned += SpawnCat;
            shift.CatRemoved += RemoveCat;
            shift.Ended += () => { Unlock(); Play(shift.Won ? workSound : scratchSound); };
            wallpaper.sharedMaterial.mainTexture = intact;
            yaw = pitch = 0;
            view.transform.rotation = Quaternion.identity;
            paused = false;
            workFlash = sprayFlash = 0;
            status = "Смена началась. Работай и прислушивайся к котам.";
        }

        private void StartShift()
        {
            ResetShift();
            started = true;
            Lock();
        }

        private void Update()
        {
            if (Input.GetKeyDown(KeyCode.Escape) && started && !shift.Finished)
            {
                paused = !paused;
                if (paused) Unlock(); else Lock();
            }
            if (shift.Finished && Input.GetKeyDown(KeyCode.R)) StartShift();
            if (!started || paused || shift.Finished) return;
            if (Cursor.lockState != CursorLockMode.Locked) return;
            yaw = Mathf.Clamp(yaw + Input.GetAxis("Mouse X") * 2.5f, -115, 115);
            pitch = Mathf.Clamp(pitch - Input.GetAxis("Mouse Y") * 2.5f, -40, 40);
            view.transform.rotation = Quaternion.Euler(pitch, yaw, 0);
            shift.Tick(Time.deltaTime);
            if (shift.Finished) return;
            if (Input.GetKeyDown(KeyCode.F))
            {
                shift.Work();
                workFlash = .18f;
                Play(workSound);
                status = shift.Quota == 100 ? "Квота готова! Береги обои до конца смены." : "Ещё одна задача закрыта. +5% к квоте.";
            }
            if (Input.GetKeyDown(KeyCode.Space))
            {
                sprayFlash = .25f;
                Play(spraySound);
                if (!shift.Shoo(CanSeeCat())) status = "Посмотри прямо на кота и нажми пробел.";
            }
            workFlash = Mathf.Max(0, workFlash - Time.deltaTime);
            sprayFlash = Mathf.Max(0, sprayFlash - Time.deltaTime);
            screen.sharedMaterial.color = workFlash > 0 ? mint : new Color(.16f, .32f, .38f);
            if (cat != null)
            {
                paw.localRotation = Quaternion.Euler(Mathf.Sin(Time.time * 18) * 25, 0, 0);
                tail.localRotation = Quaternion.Euler(0, 0, Mathf.Sin(Time.time * 5) * 18);
            }
        }

        private void OnApplicationFocus(bool focus)
        {
            if (!focus && started && shift != null && !shift.Finished) { paused = true; Unlock(); }
        }

        private bool CanSeeCat()
        {
            if (cat == null) return false;
            Vector3 direction = cat.position + Vector3.up * .7f - view.transform.position;
            return Vector3.Dot(view.transform.forward, direction.normalized) > .88f;
        }

        private void SpawnCat()
        {
            float side = UnityEngine.Random.value < .5f ? -1 : 1;
            cat = new GameObject("Mischievous cat").transform;
            cat.SetParent(room.transform);
            cat.position = new Vector3(side * 4.6f, 0, 3.6f);
            cat.rotation = Quaternion.Euler(0, side < 0 ? -65 : 65, 0);
            Color ginger = new Color(.94f, .49f, .22f);
            Part(cat, "Body", new Vector3(0, .48f, 0), new Vector3(.58f, .78f, .48f), ginger, PrimitiveType.Sphere);
            Part(cat, "Head", new Vector3(0, 1.02f, .08f), new Vector3(.62f, .52f, .5f), ginger, PrimitiveType.Sphere);
            for (int sideIndex = -1; sideIndex <= 1; sideIndex += 2)
            {
                Part(cat, "Ear", new Vector3(sideIndex * .21f, 1.3f, .04f), new Vector3(.16f, .25f, .18f), ginger);
                Part(cat, "Pink ear", new Vector3(sideIndex * .21f, 1.3f, .14f), new Vector3(.075f, .14f, .025f), coral);
                Part(cat, "Eye", new Vector3(sideIndex * .15f, 1.06f, .31f), new Vector3(.065f, .09f, .035f), ink, PrimitiveType.Sphere);
                Part(cat, "Foot", new Vector3(sideIndex * .19f, .1f, .13f), new Vector3(.2f, .16f, .35f), ginger, PrimitiveType.Sphere);
            }
            Part(cat, "Muzzle", new Vector3(0, .94f, .32f), new Vector3(.27f, .17f, .08f), Color.white, PrimitiveType.Sphere);
            Part(cat, "Nose", new Vector3(0, 1, .38f), new Vector3(.075f, .055f, .04f), coral);
            paw = Part(cat, "Scratching paw", new Vector3(.31f, .72f, .26f), new Vector3(.16f, .42f, .18f), ginger).transform;
            tail = Part(cat, "Tail", new Vector3(0, .48f, -.39f), new Vector3(.12f, .7f, .12f), ginger).transform;
            status = side < 0 ? "Ш-ш-ш… Кот слева!" : "Ш-ш-ш… Кот справа!";
            Play(meowSound);
        }

        private void RemoveCat(bool didScratch)
        {
            if (cat != null) Destroy(cat.gameObject);
            cat = null;
            if (didScratch)
            {
                wallpaper.sharedMaterial.mainTexture = shift.Damage >= 30 ? critical : scratched;
                Play(scratchSound);
                status = "Кот испортил обои! +10% повреждений.";
            }
            else status = "Пшшш! Кот убежал. Можно вернуться к работе.";
        }

        private Material MakeMaterial(Color color)
        {
            Material template = Resources.Load<Material>("GameMaterial");
            Material material = template != null ? new Material(template) : new Material(Shader.Find("Standard"));
            material.color = color;
            material.SetFloat("_Glossiness", .12f);
            materials.Add(material);
            return material;
        }

        private GameObject Part(Transform parent, string label, Vector3 position, Vector3 size, Color color, PrimitiveType shape = PrimitiveType.Cube)
        {
            GameObject part = GameObject.CreatePrimitive(shape);
            part.name = label;
            part.transform.SetParent(parent, false);
            part.transform.localPosition = position;
            part.transform.localScale = size;
            part.GetComponent<Renderer>().sharedMaterial = MakeMaterial(color);
            Destroy(part.GetComponent<Collider>());
            return part;
        }

        private void BuildRoom()
        {
            room = new GameObject("Home office");
            Transform r = room.transform;
            Color cream = new Color(.92f, .86f, .74f), wood = new Color(.57f, .35f, .23f);
            Part(r, "Floor", new Vector3(0, -.15f, 1), new Vector3(12, .3f, 12), wood);
            wallpaper = Part(r, "Wallpaper", new Vector3(0, 2.5f, 5), new Vector3(12, 5, .15f), cream).GetComponent<Renderer>();
            Part(r, "Left wall", new Vector3(-6, 2.5f, 0), new Vector3(.15f, 5, 10), new Color(.64f, .79f, .77f));
            Part(r, "Right wall", new Vector3(6, 2.5f, 0), new Vector3(.15f, 5, 10), new Color(.64f, .79f, .77f));
            Part(r, "Skirting", new Vector3(0, .15f, 4.86f), new Vector3(12, .3f, .12f), Color.white);
            Part(r, "Rug", new Vector3(0, .015f, 1), new Vector3(4.8f, .025f, 3.8f), new Color(.74f, .54f, .4f));
            Part(r, "Desktop", new Vector3(0, .9f, 1.35f), new Vector3(3.5f, .15f, 1.5f), wood);
            foreach (float x in new[] { -1.5f, 1.5f }) foreach (float z in new[] { .8f, 1.9f })
                Part(r, "Desk leg", new Vector3(x, .43f, z), new Vector3(.12f, .86f, .12f), ink);
            Part(r, "Laptop base", new Vector3(0, 1.02f, 1.2f), new Vector3(1.5f, .07f, .85f), ink);
            Part(r, "Laptop lid", new Vector3(0, 1.46f, 1.62f), new Vector3(1.5f, .9f, .08f), ink);
            screen = Part(r, "Screen", new Vector3(0, 1.46f, 1.57f), new Vector3(1.35f, .74f, .025f), mint).GetComponent<Renderer>();
            for (int row = 0; row < 4; row++)
            {
                Part(r, "Task line", new Vector3(-.08f, 1.68f - row * .14f, 1.55f), new Vector3(.88f - row * .1f, .035f, .015f), new Color(.7f, .92f, .85f));
                for (int col = 0; col < 10; col++) Part(r, "Key", new Vector3(-.6f + col * .13f, 1.061f, .96f + row * .13f), new Vector3(.09f, .012f, .08f), new Color(.4f, .5f, .52f));
            }
            Part(r, "Mug", new Vector3(-1.15f, 1.17f, 1.05f), new Vector3(.22f, .2f, .22f), coral, PrimitiveType.Cylinder);
            Part(r, "Coffee", new Vector3(-1.15f, 1.375f, 1.05f), new Vector3(.18f, .005f, .18f), wood, PrimitiveType.Cylinder);
            Part(r, "Spray bottle", new Vector3(1.15f, 1.18f, 1.05f), new Vector3(.22f, .4f, .2f), mint);
            Part(r, "Spray nozzle", new Vector3(1.15f, 1.43f, 1.02f), new Vector3(.3f, .1f, .16f), coral);
            Part(r, "Window frame", new Vector3(-3.1f, 2.8f, 4.8f), new Vector3(2.7f, 2.1f, .16f), Color.white);
            Part(r, "Blue sky", new Vector3(-3.1f, 2.8f, 4.7f), new Vector3(2.45f, 1.85f, .04f), new Color(.48f, .77f, .9f));
            Part(r, "Window cross", new Vector3(-3.1f, 2.8f, 4.65f), new Vector3(.08f, 1.9f, .06f), Color.white);
            Part(r, "Window cross", new Vector3(-3.1f, 2.8f, 4.65f), new Vector3(2.45f, .08f, .06f), Color.white);
            Part(r, "Shelf", new Vector3(2.8f, 2.7f, 4.6f), new Vector3(2.1f, .12f, .6f), wood);
            for (int i = 0; i < 6; i++) Part(r, "Book", new Vector3(2.05f + i * .22f, 3.02f, 4.6f), new Vector3(.16f, .5f + i % 2 * .12f, .35f), i % 2 == 0 ? coral : mint);
            Part(r, "Plant pot", new Vector3(3.1f, .35f, 4.3f), new Vector3(.6f, .35f, .6f), cream, PrimitiveType.Cylinder);
            Part(r, "Plant", new Vector3(3.1f, 1.1f, 4.3f), new Vector3(.9f, 1.3f, .8f), new Color(.26f, .49f, .32f), PrimitiveType.Sphere);
            GameObject cameraObject = new GameObject("Player camera");
            cameraObject.transform.SetParent(transform);
            cameraObject.transform.position = new Vector3(0, 1.8f, -.65f);
            view = cameraObject.AddComponent<Camera>();
            view.fieldOfView = 68;
            view.nearClipPlane = .05f;
            view.backgroundColor = new Color(.68f, .8f, .84f);
            cameraObject.tag = "MainCamera";
            cameraObject.AddComponent<AudioListener>();
            Light sun = new GameObject("Afternoon sunlight").AddComponent<Light>();
            sun.transform.SetParent(r);
            sun.type = LightType.Directional;
            sun.transform.rotation = Quaternion.Euler(45, -30, 0);
            sun.intensity = 1.1f;
            sun.shadows = LightShadows.Soft;
            RenderSettings.ambientLight = new Color(.65f, .69f, .72f);
        }

        private void OnGUI()
        {
            if (shift == null) return;
            GUI.matrix = Matrix4x4.TRS(Vector3.zero, Quaternion.identity, new Vector3(Screen.width / 1280f, Screen.height / 720f, 1));
            if (titleStyle == null)
            {
                titleStyle = new GUIStyle(GUI.skin.label) { fontSize = 42, fontStyle = FontStyle.Bold, wordWrap = true };
                textStyle = new GUIStyle(GUI.skin.label) { fontSize = 20, wordWrap = true };
                smallStyle = new GUIStyle(GUI.skin.label) { fontSize = 15, wordWrap = true };
                numberStyle = new GUIStyle(GUI.skin.label) { fontSize = 28, fontStyle = FontStyle.Bold };
                titleStyle.normal.textColor = textStyle.normal.textColor = smallStyle.normal.textColor = numberStyle.normal.textColor = Color.white;
            }
            Panel(new Rect(24, 24, 320, 180), new Color(.07f, .14f, .18f, .95f));
            GUI.Label(new Rect(44, 37, 280, 30), "PAWDUCTIVITY  /  СМЕНА 01", smallStyle);
            GUI.Label(new Rect(44, 68, 270, 35), "Квота  " + shift.Quota + "% / 100%", numberStyle);
            Bar(new Rect(44, 111, 276, 8), shift.Quota / 100f, mint);
            GUI.Label(new Rect(44, 131, 280, 30), "Обои: " + shift.Damage + "% / 50%", textStyle);
            Bar(new Rect(44, 168, 276, 8), shift.Damage / 50f, coral);
            Panel(new Rect(1076, 24, 180, 84), ink);
            GUI.Label(new Rect(1094, 31, 160, 24), "ДО КОНЦА СМЕНЫ", smallStyle);
            GUI.Label(new Rect(1110, 57, 140, 42), "00:" + Mathf.CeilToInt(Mathf.Max(0, ShiftState.Duration - shift.Elapsed)).ToString("00"), numberStyle);
            Panel(new Rect(24, 615, 1232, 81), new Color(.07f, .14f, .18f, .94f));
            GUI.Label(new Rect(44, 626, 1170, 31), status, textStyle);
            GUI.Label(new Rect(44, 664, 1170, 26), "МЫШЬ — осмотр   •   F — работать   •   ПРОБЕЛ — прогнать кота в поле зрения   •   ESC — пауза", smallStyle);
            if (started && !paused && !shift.Finished)
            {
                Panel(new Rect(636, 356, 8, 8), CanSeeCat() ? mint : Color.white);
                if (shift.CatActive)
                {
                    Panel(new Rect(458, 24, 364, 68), ink);
                    GUI.Label(new Rect(478, 34, 340, 28), "КОТ ДЕРЁТ ОБОИ!  " + shift.CatRemaining.ToString("0.0") + " c", textStyle);
                    Bar(new Rect(478, 74, 324, 5), shift.CatRemaining / ShiftState.ScratchDelay, coral);
                }
                if (sprayFlash > 0) Panel(new Rect(0, 0, 1280, 720), new Color(.6f, .92f, 1, sprayFlash * .4f));
            }
            if (!started) Modal("PAWDUCTIVITY", "Удалённая работа с котами", "За 40 секунд выполни 100% квоты: каждое нажатие F даёт 5%.\nКотам хватает 5 секунд, чтобы испортить обои. Посмотри на кота и нажми пробел. При 50% повреждений смена проиграна.", "Начать смену", StartShift);
            else if (shift.Finished) Modal(shift.Won ? "СМЕНА ЗАКРЫТА!" : "СМЕНА НЕ УДАЛАСЬ", shift.Won ? "Работа сделана. Коты под контролем." : shift.Damage >= 50 ? "Обои уничтожены. Арендодатель недоволен." : "Не хватило выполненных задач.", "Квота: " + shift.Quota + "%   •   Повреждения: " + shift.Damage + "%\nНовая смена — новая попытка. Нажми R или кнопку ниже.", "Ещё одну смену", StartShift);
            else if (paused) Modal("ПАУЗА", "Можно выдохнуть.", "Время смены и таймер кота остановлены.", "Продолжить", () => { paused = false; Lock(); });
        }

        private void Modal(string title, string subtitle, string body, string button, Action action)
        {
            Panel(new Rect(0, 0, 1280, 720), new Color(.03f, .07f, .1f, .7f));
            Panel(new Rect(310, 160, 660, 400), ink);
            GUI.Label(new Rect(346, 190, 590, 70), title, titleStyle);
            GUI.Label(new Rect(346, 266, 585, 55), subtitle, textStyle);
            GUI.Label(new Rect(346, 326, 585, 142), body, textStyle);
            Color previous = GUI.backgroundColor;
            GUI.backgroundColor = mint;
            var buttonStyle = new GUIStyle(GUI.skin.button) { fontSize = 22, fontStyle = FontStyle.Bold };
            if (GUI.Button(new Rect(346, 478, 585, 52), button, buttonStyle)) action();
            GUI.backgroundColor = previous;
        }

        private static void Panel(Rect rect, Color color) { Color old = GUI.color; GUI.color = color; GUI.DrawTexture(rect, Texture2D.whiteTexture); GUI.color = old; }
        private static void Bar(Rect rect, float value, Color color) { Panel(rect, new Color(.25f, .31f, .34f)); rect.width *= Mathf.Clamp01(value); Panel(rect, color); }
        private static void Lock() { Cursor.lockState = CursorLockMode.Locked; Cursor.visible = false; }
        private static void Unlock() { Cursor.lockState = CursorLockMode.None; Cursor.visible = true; }
        private void Play(AudioClip clip) { speaker.PlayOneShot(clip, .25f); }

        private static AudioClip Tone(float frequency, float duration, int type)
        {
            const int rate = 22050;
            float[] samples = new float[(int)(rate * duration)];
            var noise = new System.Random(42);
            for (int i = 0; i < samples.Length; i++)
            {
                float t = i / (float)rate;
                float envelope = Mathf.Sin(Mathf.PI * i / samples.Length);
                samples[i] = envelope * (type == 2 ? (float)(noise.NextDouble() * 2 - 1) * .4f : Mathf.Sin(2 * Mathf.PI * frequency * t + (type == 1 ? 8 * Mathf.Sin(t * 10) : 0)) * .4f);
            }
            AudioClip clip = AudioClip.Create("Synthesized office sound", samples.Length, 1, rate, false);
            clip.SetData(samples, 0);
            return clip;
        }

        private void OnDestroy()
        {
            Unlock();
            foreach (Material material in materials) if (material != null) Destroy(material);
            foreach (AudioClip clip in new[] { workSound, meowSound, spraySound, scratchSound }) if (clip != null) Destroy(clip);
            if (room != null) Destroy(room);
        }
    }
}
