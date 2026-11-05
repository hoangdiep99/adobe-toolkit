using System;
using System.IO;
using System.Management.Automation;
using System.Management.Automation.Runspaces;
using System.Reflection;
using System.Runtime.InteropServices;
using System.Text;
using System.Windows.Forms;

[assembly: AssemblyTitle("Adobe Toolkit")]
[assembly: AssemblyDescription("Adobe Diagnostic & Clean Utility for Windows")]
[assembly: AssemblyCompany("HoangDiep Tools")]
[assembly: AssemblyProduct("Adobe Toolkit")]
[assembly: AssemblyCopyright("Copyright (c) 2026 HoangDiep")]
[assembly: AssemblyVersion("1.0.0.0")]
[assembly: AssemblyFileVersion("1.0.0.0")]
[assembly: ComVisible(false)]
[assembly: Guid("9b8a7d6c-5e4f-4a3b-8c2d-1e0f9a8b7c6d")]

namespace AdobeToolkitApp {
    internal static class Program {
        [STAThread]
        private static int Main(string[] args) {
            Application.EnableVisualStyles();
            Application.SetCompatibleTextRenderingDefault(false);
            try {
                string scriptText;
                Assembly asm = Assembly.GetExecutingAssembly();
                using (Stream s = asm.GetManifestResourceStream("AdobeToolkit.Script.ps1")) {
                    if (s == null) {
                        MessageBox.Show("Embedded script resource not found.", "Adobe Toolkit", MessageBoxButtons.OK, MessageBoxIcon.Error);
                        return 1;
                    }
                    using (StreamReader sr = new StreamReader(s, Encoding.UTF8)) {
                        scriptText = sr.ReadToEnd();
                    }
                }
                if (args != null && args.Length > 0 && args[0] == "--verify-only") {
                    return scriptText.Length > 100 ? 0 : 2;
                }

                InitialSessionState iss = InitialSessionState.CreateDefault();
                iss.ApartmentState = System.Threading.ApartmentState.STA;
                iss.ThreadOptions = PSThreadOptions.UseCurrentThread;
                using (Runspace rs = RunspaceFactory.CreateRunspace(iss)) {
                    rs.Open();
                    Runspace.DefaultRunspace = rs;
                    using (PowerShell ps = PowerShell.Create()) {
                        ps.Runspace = rs;
                        ps.AddScript(scriptText);
                        ps.Invoke();
                        if (ps.HadErrors && ps.Streams.Error.Count > 0) {
                            MessageBox.Show(ps.Streams.Error[0].Exception.Message, "Adobe Toolkit", MessageBoxButtons.OK, MessageBoxIcon.Error);
                            return 1;
                        }
                    }
                }
                return 0;
            } catch (Exception ex) {
                MessageBox.Show(ex.Message, "Adobe Toolkit", MessageBoxButtons.OK, MessageBoxIcon.Error);
                return 1;
            }
        }
    }
}