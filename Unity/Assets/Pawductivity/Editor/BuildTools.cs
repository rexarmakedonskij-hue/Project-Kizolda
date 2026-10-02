using System;
using System.IO;
using UnityEditor;
using UnityEditor.Build.Reporting;
using UnityEngine;

namespace Pawductivity.Editor
{
    public static class BuildTools
    {
        private const string ScenePath = "Assets/Pawductivity/Scenes/Main.unity";

        [InitializeOnLoadMethod]
        private static void OnLoad() { EditorApplication.delayCall += Configure; }

        private static void Configure()
        {
            if (EditorApplication.isPlayingOrWillChangePlaymode) return;
            if (!File.Exists("Assets/Resources/GameMaterial.mat"))
            {
                var material = new Material(Shader.Find("Standard"));
                material.SetFloat("_Glossiness", .12f);
                AssetDatabase.CreateAsset(material, "Assets/Resources/GameMaterial.mat");
                AssetDatabase.SaveAssets();
            }
            EditorBuildSettings.scenes = new[] { new EditorBuildSettingsScene(ScenePath, true) };
            PlayerSettings.companyName = "Project Kizolda";
            PlayerSettings.productName = "Pawductivity";
            PlayerSettings.defaultScreenWidth = 1280;
            PlayerSettings.defaultScreenHeight = 720;
            PlayerSettings.runInBackground = false;
        }

        [MenuItem("Pawductivity/Validate game rules")]
        public static void Validate()
        {
            var state = new ShiftState(1);
            Require(state.Quota == 0 && state.Damage == 0 && !state.Finished, "Initial state");
            state.Work();
            Require(state.Quota == 5, "Work adds five percent");
            for (int i = 0; i < 40; i++) state.Work();
            Require(state.Quota == 100, "Quota is capped");
            state.Tick(4);
            Require(state.CatActive && state.CatRemaining == 5, "First cat at four seconds");
            Require(!state.Shoo(false) && state.CatActive, "Cannot shoo outside field of view");
            Require(state.Shoo(true) && !state.CatActive, "Visible cat can be chased");
            Require(state.NextCat >= 5 && state.NextCat <= 9, "Respawn interval");
            var damaged = new ShiftState(7);
            int removed = 0;
            damaged.CatRemoved += _ => removed++;
            damaged.Tick(9);
            Require(damaged.Damage == 10 && !damaged.CatActive && removed == 1, "Scratch removes cat once");
            damaged.Tick(1);
            Require(damaged.Damage == 10 && removed == 1, "No ghost scratches");
            var lost = new ShiftState(3);
            lost.Tick(41);
            Require(lost.Finished && !lost.Won, "Missing quota loses");
            int quota = lost.Quota, damage = lost.Damage;
            lost.Work(); lost.Tick(100); lost.Shoo(true);
            Require(lost.Quota == quota && lost.Damage == damage, "Finished state is frozen");
            var won = new ShiftState(5);
            for (int i = 0; i < 20; i++) won.Work();
            for (int i = 0; i < 500; i++) { won.Tick(.1f); won.Shoo(true); }
            Require(won.Finished && won.Won && won.Damage == 0, "Full successful shift");
            var large = new ShiftState(11);
            var small = new ShiftState(11);
            large.Tick(30);
            for (int i = 0; i < 30; i++) small.Tick(1);
            Require(large.Damage == small.Damage && large.CatActive == small.CatActive && Mathf.Abs(large.Elapsed - small.Elapsed) < .001f, "Frame duration independence");
            Debug.Log("Pawductivity: all 13 rule checks passed.");
        }

        private static void Require(bool condition, string label)
        {
            if (!condition) throw new InvalidOperationException("Pawductivity validation failed: " + label);
        }

        [MenuItem("Pawductivity/Build macOS")]
        public static void BuildMac() { Build(BuildTarget.StandaloneOSX, "Builds/macOS/Pawductivity.app"); }

        [MenuItem("Pawductivity/Build Windows")]
        public static void BuildWindows() { Build(BuildTarget.StandaloneWindows64, "Builds/Windows/Pawductivity.exe"); }

        private static void Build(BuildTarget target, string path)
        {
            Configure();
            Validate();
            Directory.CreateDirectory(Path.GetDirectoryName(path));
            BuildReport report = BuildPipeline.BuildPlayer(new BuildPlayerOptions
            {
                scenes = new[] { ScenePath }, locationPathName = path, target = target,
                options = BuildOptions.None
            });
            if (report.summary.result != BuildResult.Succeeded)
                throw new InvalidOperationException("Build failed: " + report.summary.result);
        }
    }
}
