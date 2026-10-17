$ErrorActionPreference = 'Stop'
$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$baselineCommit = '547789ced2db220737efd5327ddab8502a460d41'
$testOutput = Join-Path ([IO.Path]::GetTempPath()) ('TeknoParrotUI-RawInputFocus-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory $testOutput | Out-Null

function Read-Method([string]$source, [string]$signature) {
    $start = $source.IndexOf($signature)
    if ($start -lt 0) { throw "Method not found: $signature" }
    $brace = $source.IndexOf('{', $start)
    $depth = 1
    $end = $brace + 1
    while ($depth -gt 0 -and $end -lt $source.Length) {
        if ($source[$end] -eq '{') { $depth++ }
        if ($source[$end] -eq '}') { $depth-- }
        $end++
    }
    if ($depth -ne 0) { throw "Unbalanced method: $signature" }
    $source.Substring($start, $end - $start).Replace('private void KeepCursorInTextBox', 'public void KeepCursorInTextBox').Replace('private TextBox GetActiveTextBox', 'public TextBox GetActiveTextBox')
}

function Read-Baseline([string]$path) {
    $source = & git -C $repoRoot show "${baselineCommit}:$path"
    if ($LASTEXITCODE -ne 0) { throw "Cannot read baseline file: $path" }
    $source -join [Environment]::NewLine
}

$cursorPath = 'TeknoParrotUi/UserControls/JoystickControl.xaml.cs'
$focusPath = 'TeknoParrotUi/Helpers/JoystickControlRawInput.cs'
$cursorSignature = 'private void KeepCursorInTextBox(TextBox box)'
$focusSignature = 'private TextBox GetActiveTextBox()'
$baseline = Read-Method (Read-Baseline $cursorPath) $cursorSignature
$fixed = Read-Method ([IO.File]::ReadAllText((Join-Path $repoRoot $cursorPath))) $cursorSignature
$baselineFocus = Read-Method (Read-Baseline $focusPath) $focusSignature
$fixedFocus = Read-Method ([IO.File]::ReadAllText((Join-Path $repoRoot $focusPath))) $focusSignature
$stub = @'
public struct RECT { public int Left, Top, Right, Bottom; }
public RECT LastRect;
public int ClipCalls;
private bool ClipCursor(ref RECT rect) { LastRect = rect; ClipCalls++; return true; }
'@
$code = @"
using System;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Input;
namespace RawInputFocusRegression {
public class Baseline { $stub $baseline }
public class Fixed { $stub $fixed }
public class BaselineFocus { $baselineFocus }
public class FixedFocus { $fixedFocus }
public static class Runner {
 [STAThread] public static void Main() {
  var app = new Application { ShutdownMode = ShutdownMode.OnExplicitShutdown };
  var policy = new Window { Width=300, Height=150, Left=-10000, Top=-10000, ShowInTaskbar=false, ShowActivated=false };
  var owner = new Window { Width=500, Height=300, Left=-9000, Top=-9000, ShowInTaskbar=false, ShowActivated=false };
  var box = new TextBox { Width=180, Height=40, Margin=new Thickness(20), HorizontalAlignment=HorizontalAlignment.Left, VerticalAlignment=VerticalAlignment.Top };
  owner.Content=box;
  policy.Show(); policy.Hide(); owner.Show(); owner.UpdateLayout();
  app.MainWindow=policy;
  try {
   bool reproduced=false;
   try { new Baseline().KeepCursorInTextBox(box); }
   catch(InvalidOperationException) { reproduced=true; }
   if(!reproduced) throw new Exception("Baseline did not reproduce the hidden-policy ancestor failure");
   Console.WriteLine("PASS: baseline reproduces hidden-policy ancestor failure");
   var fix=new Fixed(); fix.KeepCursorInTextBox(box);
   var origin=box.PointToScreen(new Point(1,1));
   var end=box.PointToScreen(new Point(box.ActualWidth,box.ActualHeight));
   if(fix.ClipCalls!=1 || fix.LastRect.Left!=(int)origin.X || fix.LastRect.Top!=(int)origin.Y || fix.LastRect.Right!=(int)end.X || fix.LastRect.Bottom!=(int)end.Y)
    throw new Exception("Fixed rectangle does not match actual control screen coordinates");
   Console.WriteLine("PASS: fixed clipping uses actual control coordinates with an unrelated MainWindow");
   owner.Activate(); box.Focus();
   if(Keyboard.FocusedElement!=box) throw new Exception("Harness could not focus the binding field");
   if(new BaselineFocus().GetActiveTextBox()!=null) throw new Exception("Baseline unexpectedly found focus through the hidden policy");
   if(new FixedFocus().GetActiveTextBox()!=box) throw new Exception("Fixed RawInput did not find the focused binding field");
   FocusManager.SetFocusedElement(FocusManager.GetFocusScope(box),null); Keyboard.ClearFocus();
   if(FocusManager.GetFocusedElement(owner)!=null) throw new Exception("Binding focus was not cleared");
   Console.WriteLine("PASS: RawInput finds and clears binding focus with hidden policy Windows[0]");
   app.MainWindow=owner; fix.KeepCursorInTextBox(box);
   if(fix.ClipCalls!=2) throw new Exception("Normal window scenario did not clip");
   Console.WriteLine("PASS: normal owner window clips successfully");
   fix.KeepCursorInTextBox(new TextBox());
   if(fix.ClipCalls!=2) throw new Exception("Detached control unexpectedly clipped the cursor");
   Console.WriteLine("PASS: detached control returns without clipping or throwing");
  } finally { owner.Close(); policy.Close(); app.Shutdown(); }
 }
}
}
"@
$generated = Join-Path $testOutput 'Regression.generated.cs'
$testExe = Join-Path $testOutput 'Regression.exe'
$code | Set-Content $generated
$vswhere = "${env:ProgramFiles(x86)}\Microsoft Visual Studio\Installer\vswhere.exe"
$compiler = & $vswhere -latest -products '*' -requires Microsoft.Component.MSBuild -find 'MSBuild\**\Bin\Roslyn\csc.exe' | Select-Object -First 1
if (!$compiler) { throw 'Visual Studio Roslyn compiler was not found.' }
$refs = "${env:ProgramFiles(x86)}\Reference Assemblies\Microsoft\Framework\.NETFramework\v4.6.2"
& $compiler /nologo /langversion:9 /target:exe /platform:x86 "/out:$testExe" "/r:$refs\PresentationFramework.dll" "/r:$refs\PresentationCore.dll" "/r:$refs\WindowsBase.dll" "/r:$refs\System.Xaml.dll" $generated
if ($LASTEXITCODE -ne 0) { throw 'Regression harness compilation failed.' }
& $testExe
if ($LASTEXITCODE -ne 0) { throw 'Regression harness failed.' }
Write-Output "Test artifacts: $testOutput"
