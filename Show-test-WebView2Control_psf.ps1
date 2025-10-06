
    Add-Type -AssemblyName System.Windows.Forms
    Add-Type -AssemblyName System.Drawing
[reflection.assembly]::LoadFrom("C:\Users\mark\AppData\Local\OmadaWeb.PS\Bin\Core\Microsoft.Web.WebView2\Microsoft.Web.WebView2.Core.dll")

    [reflection.assembly]::LoadFrom("C:\Users\mark\AppData\Local\OmadaWeb.PS\Bin\Core\Microsoft.Web.WebView2\Microsoft.Web.WebView2.WinForms.dll")

function Show-test-WebView2Control_psf {

#----------------------------------------------
#region Import the Assemblies
#----------------------------------------------
# I've put the following files in `C:\users\davris\tmp\wv2`
#     Microsoft.Web.WebView2.Core.dll
#     Microsoft.Web.WebView2.WinForms.dll
#     WebView2Loader.dll


#[void][reflection.assembly]::Load('System.Drawing, Version=4.0.0.0, Culture=neutral, PublicKeyToken=b03f5f7f11d50a3a')
#[void][reflection.assembly]::Load('System.Windows.Forms, Version=4.0.0.0, Culture=neutral, PublicKeyToken=b77a5c561934e089')
#endregion Import Assemblies

#----------------------------------------------
#region Generated Form Objects
#----------------------------------------------

[System.Windows.Forms.Application]::EnableVisualStyles()
$form1 = New-Object System.Windows.Forms.Form
$buttonRefresh = New-Object System.Windows.Forms.Button
$buttonGo = New-Object System.Windows.Forms.Button
$textbox1 = New-Object System.Windows.Forms.TextBox
Wait-Debugger

[Microsoft.Web.WebView2.WinForms.WebView2] $webview = New-Object Microsoft.Web.WebView2.WinForms.WebView2
$webview.CreationProperties = New-Object Microsoft.Web.WebView2.WinForms.CoreWebView2CreationProperties
new-item -Path "$env:temp\TestWebView2" -ItemType Directory -Force | Out-Null
$webview.CreationProperties.UserDataFolder = "$env:temp\TestWebView2"

$InitialFormWindowState = New-Object System.Windows.Forms.FormWindowState
#endregion Generated Form Objects

#----------------------------------------------
# User Generated Script
#----------------------------------------------

$form1_Load={
    #TODO: Initialize Form Controls here
    $webview.Source = ([uri]::new($textbox1.Text))
    $webview.Visible = $true
}

$buttonGo_Click={
    #TODO: Place custom script here
    $webview.Source = [System.Uri] $textbox1.Text;
}

$webview_SourceChanged={
    $form1.Text = $webview.Source.AbsoluteUri;
}

# --End User Generated Script--
#----------------------------------------------
#region Generated Events
#----------------------------------------------

$Form_StateCorrection_Load=
{
    #Correct the initial state of the form to prevent the .Net maximized form issue
    $form1.WindowState = $InitialFormWindowState
}

$Form_Cleanup_FormClosed=
{
    #Remove all event handlers from the controls
    try
    {
        $buttonGo.remove_Click($buttonGo_Click)
        $webview.remove_SourceChanged($webview_SourceChanged)
        $form1.remove_Load($form1_Load)
        $form1.remove_Load($Form_StateCorrection_Load)
        $form1.remove_FormClosed($Form_Cleanup_FormClosed)
    }
    catch { Out-Null <# Prevent PSScriptAnalyzer warning #> }
}
#endregion Generated Events

#----------------------------------------------
#region Generated Form Code
#----------------------------------------------
$form1.SuspendLayout()
#
# form1
#
$form1.Controls.Add($buttonRefresh)
$form1.Controls.Add($buttonGo)
$form1.Controls.Add($textbox1)
$form1.Controls.Add($webview)
$form1.AutoScaleDimensions = New-Object System.Drawing.SizeF(6, 13)
$form1.AutoScaleMode = 'Font'
$form1.ClientSize = New-Object System.Drawing.Size(619, 413)
$form1.Name = 'form1'
$form1.Text = 'Form'
$form1.add_Load($form1_Load)
#
# buttonRefresh
#
$buttonRefresh.Location = New-Object System.Drawing.Point(13, 13)
$buttonRefresh.Name = 'buttonRefresh'
$buttonRefresh.Size = New-Object System.Drawing.Size(75, 23)
$buttonRefresh.TabIndex = 3
$buttonRefresh.Text = 'Refresh'
$buttonRefresh.UseVisualStyleBackColor = $True
#
# buttonGo
#
$buttonGo.Location = New-Object System.Drawing.Point(538, 9)
$buttonGo.Name = 'buttonGo'
$buttonGo.Size = New-Object System.Drawing.Size(75, 23)
$buttonGo.TabIndex = 2
$buttonGo.Text = 'Go'
$buttonGo.UseVisualStyleBackColor = $True
$buttonGo.add_Click($buttonGo_Click)
#
# textbox1
#
$textbox1.Location = New-Object System.Drawing.Point(96, 13)
$textbox1.Name = 'textbox1'
$textbox1.Size = New-Object System.Drawing.Size(435, 20)
$textbox1.TabIndex = 1
$textbox1.Text = 'https://www.bing.com'
#
# webview
#
$webview.Location = New-Object System.Drawing.Point(0, 49)
$webview.Name = 'webview'
$webview.Size = New-Object System.Drawing.Size(619, 364)
$webview.TabIndex = 0
$webview.ZoomFactor = 1
$webview.add_SourceChanged($webview_SourceChanged)

$form1.ResumeLayout()
#endregion Generated Form Code

#----------------------------------------------

#Save the initial state of the form
$InitialFormWindowState = $form1.WindowState
#Init the OnLoad event to correct the initial state of the form
$form1.add_Load($Form_StateCorrection_Load)
#Clean up the control events
$form1.add_FormClosed($Form_Cleanup_FormClosed)
#Show the Form
    return $form1.ShowDialog()

} #End Function

    #Call the form
    Show-test-WebView2Control_psf | Out-Null