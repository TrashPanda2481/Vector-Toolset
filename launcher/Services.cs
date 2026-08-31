using System;
using System.Diagnostics;
using System.IO;
using Microsoft.Win32;
using Newtonsoft.Json;
using Newtonsoft.Json.Serialization;
using Vector.Launcher.Models;

namespace Vector.Launcher.Services
{
    public enum PlaneEnv { Live, WinPE }

    public enum ToolState { Ready, NotFound, Builtin, Planned, LiveOnly }

    public static class EnvironmentService
    {
        public static PlaneEnv Current
        {
            get { return IsWinPE() ? PlaneEnv.WinPE : PlaneEnv.Live; }
        }

        public static bool IsWinPE()
        {
            // WinPE marks itself with the MiniNT control key.
            try
            {
                using (var k = Registry.LocalMachine.OpenSubKey(@"SYSTEM\CurrentControlSet\Control\MiniNT"))
                {
                    if (k != null) return true;
                }
            }
            catch { }

            // Fallback: WinPE runs from X:.
            try
            {
                var sd = Environment.GetEnvironmentVariable("SystemDrive");
                if (string.Equals(sd, "X:", StringComparison.OrdinalIgnoreCase)) return true;
            }
            catch { }

            return false;
        }
    }

    public static class PathResolver
    {
        // Find the toolset root by the .toolset-root marker.
        // Prefer a mounted drive whose root carries the populated toolkit (the
        // USB data partition), so a WinPE-baked launcher uses the full tool set
        // rather than its own minimal baked copy. Then fall back to walking up
        // from the launcher (dev, and the baked core when no data partition).
        public static string FindRoot()
        {
            try
            {
                foreach (var d in DriveInfo.GetDrives())
                {
                    try
                    {
                        var r = d.RootDirectory.FullName;
                        if (d.IsReady
                            && File.Exists(Path.Combine(r, ".toolset-root"))
                            && Directory.Exists(Path.Combine(r, "tools")))
                            return r;
                    }
                    catch { }
                }
            }
            catch { }

            try
            {
                var dir = new DirectoryInfo(AppDomain.CurrentDomain.BaseDirectory);
                while (dir != null)
                {
                    if (File.Exists(Path.Combine(dir.FullName, ".toolset-root"))) return dir.FullName;
                    dir = dir.Parent;
                }
            }
            catch { }

            return AppDomain.CurrentDomain.BaseDirectory;
        }
    }

    public static class ManifestService
    {
        public static Manifest LoadManifest(string root)
        {
            var p = Path.Combine(root, "config", "tools-manifest.json");
            var json = File.ReadAllText(p);
            return JsonConvert.DeserializeObject<Manifest>(json) ?? new Manifest();
        }

        public static ShopConfig LoadShop(string root)
        {
            try
            {
                var p = Path.Combine(root, "config", "shop.json");
                if (File.Exists(p))
                    return JsonConvert.DeserializeObject<ShopConfig>(File.ReadAllText(p)) ?? new ShopConfig();
            }
            catch { }
            return new ShopConfig();
        }

        public static void Save(string root, Manifest manifest)
        {
            var settings = new JsonSerializerSettings
            {
                Formatting = Formatting.Indented,
                NullValueHandling = NullValueHandling.Ignore,
                ContractResolver = new CamelCasePropertyNamesContractResolver()
            };
            var json = JsonConvert.SerializeObject(manifest, settings);
            File.WriteAllText(Path.Combine(root, "config", "tools-manifest.json"), json);
        }
    }

    public static class ToolService
    {
        public static string FullPath(string root, Tool t)
        {
            // Resolve the tool path under the toolkit root, and refuse anything
            // that escapes it (an absolute path or one using ".."). A manifest can
            // be authored or shared by anyone, so it is not fully trusted.
            var rel = (t.Path ?? "").Replace('/', '\\');
            try
            {
                var rootFull = Path.GetFullPath(root);
                var full = Path.GetFullPath(Path.Combine(rootFull, rel));
                var baseDir = rootFull.TrimEnd('\\') + "\\";
                if (!full.StartsWith(baseDir, StringComparison.OrdinalIgnoreCase)) return "";
                return full;
            }
            catch { return ""; }
        }

        public static bool Exists(string root, Tool t)
        {
            if (t.Type == "builtin") return true;
            try
            {
                var full = FullPath(root, t);
                return File.Exists(full) || Directory.Exists(full);
            }
            catch { return false; }
        }

        public static ToolState State(string root, Tool t, PlaneEnv env)
        {
            if (env == PlaneEnv.WinPE && t.Plane == "live") return ToolState.LiveOnly;
            if (t.Status == "planned") return ToolState.Planned;
            if (t.Type == "script" || t.Type == "builtin") return ToolState.Builtin;
            return Exists(root, t) ? ToolState.Ready : ToolState.NotFound;
        }

        public static bool IsLaunchable(ToolState s)
        {
            return s == ToolState.Ready || s == ToolState.Builtin;
        }

        public static void Launch(string root, Tool t)
        {
            if (t.Type == "builtin")
            {
                // Native WinPE command (for example diskpart). Quote it.
                Start("cmd.exe", "/k \"" + t.Path + "\"", null);
                return;
            }

            var full = FullPath(root, t);
            if (string.IsNullOrEmpty(full))
                throw new InvalidOperationException("Tool path is outside the toolkit and was blocked: " + t.Path);

            if (t.Type == "script")
            {
                var args = "-ExecutionPolicy Bypass -NoProfile -NoExit -File \"" + full + "\" -ToolsetRoot \"" + root + "\"";
                Start("powershell.exe", args, null);
                return;
            }

            if (Directory.Exists(full)) { Start("explorer.exe", "\"" + full + "\"", null); return; }
            if (t.Console) Start("cmd.exe", "/k \"" + full + "\"", Path.GetDirectoryName(full));
            else Start(full, "", Path.GetDirectoryName(full));
        }

        private static void Start(string exe, string args, string workingDir)
        {
            var psi = new ProcessStartInfo
            {
                FileName = exe,
                Arguments = args,
                UseShellExecute = true
            };
            if (!string.IsNullOrEmpty(workingDir)) psi.WorkingDirectory = workingDir;
            Process.Start(psi);
        }
    }
}
