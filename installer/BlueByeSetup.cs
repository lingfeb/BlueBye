// BlueBye standalone setup - one exe, no dependencies.
// The engine scripts are embedded as resources; on start they are extracted to
// a temp folder and install.ps1 is executed. Exit code 0 means installed.
//
// Build:  powershell -File installer/build.ps1
// Silent: BlueBye-Setup.exe --silent   (no windows, useful for CI)

using System;
using System.Diagnostics;
using System.Drawing;
using System.IO;
using System.Reflection;
using System.Threading.Tasks;
using System.Windows.Forms;

namespace BlueBye
{
    internal static class Program
    {
        private const string AppTitle = "BlueBye 安装程序";
        private static Task<int> _work;
        private static string _temp;

        [STAThread]
        private static void Main(string[] rawArgs)
        {
            bool silent = rawArgs != null && Array.IndexOf(rawArgs, "--silent") >= 0;

            Application.EnableVisualStyles();
            Application.SetCompatibleTextRenderingDefault(false);

            if (silent)
            {
                int code = RunInstall();
                Environment.ExitCode = code;
                return;
            }

            using (var form = new SetupForm())
            {
                form.Shown += delegate
                {
                    _work = Task.Run(() => RunInstall());
                    var timer = new Timer { Interval = 200 };
                    timer.Tick += delegate
                    {
                        if (_work.IsCompleted)
                        {
                            timer.Stop();
                            form.Close();
                        }
                    };
                    timer.Start();
                };
                Application.Run(form);
            }

            int exitCode = _work != null && _work.IsCompleted ? _work.Result : -1;
            if (exitCode == 0)
            {
                var answer = MessageBox.Show(
                    "BlueBye 安装完成。\r\n\r\n现在打开设置界面吗？",
                    AppTitle, MessageBoxButtons.YesNo, MessageBoxIcon.Information);
                if (answer == DialogResult.Yes) OpenApp();
            }
            else
            {
                MessageBox.Show(
                    "安装失败（退出码 " + exitCode + "）。\r\n\r\n日志：" + Path.Combine(
                        Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
                        "BlueBye", "bluebye.log"),
                    AppTitle, MessageBoxButtons.OK, MessageBoxIcon.Error);
            }
        }

        private static void Log(string message)
        {
            string[] targets = new string[]
            {
                Path.Combine(AppDomain.CurrentDomain.BaseDirectory, "setup-debug.log"),
                Path.Combine(Path.GetTempPath(), "bluebye-setup.log")
            };
            foreach (string target in targets)
            {
                try
                {
                    File.AppendAllText(target,
                        DateTime.Now.ToString("HH:mm:ss") + "  " + message + Environment.NewLine);
                    return;
                }
                catch { }
            }
        }

        private static int RunInstall()
        {
            try
            {
                string localAppData = Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData);
                Log("user=" + Environment.UserName + " localappdata=[" + localAppData + "] temp=[" + Path.GetTempPath() + "]");
                _temp = Path.Combine(
                    localAppData,
                    "BlueBye-setup-" + Guid.NewGuid().ToString("N").Substring(0, 8));
                try
                {
                    Directory.CreateDirectory(_temp);
                }
                catch (Exception first)
                {
                    Log("local create failed: " + first.GetType().Name + ": " + first.Message);
                    _temp = Path.Combine(Path.GetTempPath(), "BlueBye-setup-" + Guid.NewGuid().ToString("N").Substring(0, 8));
                    Directory.CreateDirectory(_temp);
                }
                Log("temp=" + _temp);

                var asm = Assembly.GetExecutingAssembly();
                int count = 0;
                foreach (string name in asm.GetManifestResourceNames())
                {
                    using (Stream s = asm.GetManifestResourceStream(name))
                    using (FileStream f = File.Create(Path.Combine(_temp, name)))
                    {
                        s.CopyTo(f);
                        count++;
                        Log("resource " + name + " (" + f.Length + " bytes)");
                    }
                }
                Log("resources=" + count);

                string ps = Path.Combine(
                    Environment.GetFolderPath(Environment.SpecialFolder.System),
                    @"WindowsPowerShell\v1.0\powershell.exe");

                var psi = new ProcessStartInfo(ps)
                {
                    Arguments = "-NoProfile -ExecutionPolicy Bypass -File \"" +
                                Path.Combine(_temp, "install.ps1") + "\"",
                    UseShellExecute = false,
                    CreateNoWindow = true,
                    WorkingDirectory = _temp
                };

                using (Process p = Process.Start(psi))
                {
                    p.WaitForExit();
                    Log("child exit=" + p.ExitCode);
                    return p.ExitCode;
                }
            }
            catch (Exception ex)
            {
                Log("EXCEPTION " + ex);
                return -1;
            }
            finally
            {
                try { if (_temp != null && Directory.Exists(_temp)) Directory.Delete(_temp, true); }
                catch { }
            }
        }

        private static void OpenApp()
        {
            try
            {
                string lnk = Path.Combine(
                    Environment.GetFolderPath(Environment.SpecialFolder.DesktopDirectory),
                    "BlueBye.lnk");
                if (File.Exists(lnk)) Process.Start(lnk);
            }
            catch { }
        }
    }

    internal sealed class SetupForm : Form
    {
        public SetupForm()
        {
            Text = "BlueBye 安装程序";
            FormBorderStyle = FormBorderStyle.FixedDialog;
            MaximizeBox = false;
            MinimizeBox = false;
            StartPosition = FormStartPosition.CenterScreen;
            ClientSize = new Size(440, 168);
            BackColor = Color.FromArgb(245, 247, 252);
            Font = new Font("Microsoft YaHei UI", 9f);

            try { Icon = Icon.ExtractAssociatedIcon(Application.ExecutablePath); }
            catch { }

            var title = new Label
            {
                Text = "正在安装 BlueBye",
                Font = new Font("Microsoft YaHei UI", 15f, FontStyle.Bold),
                ForeColor = Color.FromArgb(44, 52, 80),
                AutoSize = true,
                Location = new Point(28, 26)
            };

            var hint = new Label
            {
                Text = "会注册开机任务、生成桌面快捷方式，不需要管理员权限。",
                ForeColor = Color.FromArgb(94, 106, 133),
                AutoSize = true,
                Location = new Point(30, 68)
            };

            var bar = new ProgressBar
            {
                Style = ProgressBarStyle.Marquee,
                MarqueeAnimationSpeed = 40,
                Location = new Point(30, 104),
                Size = new Size(380, 10)
            };

            Controls.Add(title);
            Controls.Add(hint);
            Controls.Add(bar);
        }
    }
}
