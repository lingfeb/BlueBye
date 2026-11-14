# bluebye-ui.ps1 - BlueBye settings window (WPF, light cute theme).
# Chinese literals: this file must be saved as UTF-8 *with BOM* (see dev/set-bom.ps1).

param([switch]$SelfTest, [switch]$Tray)

$ErrorActionPreference = 'Stop'

Add-Type -AssemblyName PresentationFramework
Add-Type -AssemblyName PresentationCore
Add-Type -AssemblyName WindowsBase
Add-Type -AssemblyName System.Xaml

$here = Split-Path -Parent $MyInvocation.MyCommand.Path
. (Join-Path $here 'bluebye-lib.ps1')
$script:Quiet = $true

$script:EnginePath = Join-Path $here 'bluebye.ps1'
$script:TaskName = 'BlueBye-Host'
$script:TaskNames = @('BlueBye-Host', 'BlueBye-Watchdog', 'BlueBye-Tray')

# single instance
$script:Mutex = New-Object System.Threading.Mutex($false, 'Local\BlueByeUI')
$got = $false
try { $got = $script:Mutex.WaitOne(0) } catch [System.Threading.AbandonedMutexException] { $got = $true }
if (-not $got) {
  # another instance is already living in the tray: ask it to show its window
  try {
    $ev = [System.Threading.EventWaitHandle]::OpenExisting('Local\BlueByeShow')
    [void]$ev.Set()
    $ev.Dispose()
  } catch { }
  return
}
$script:ShowEvent = New-Object System.Threading.EventWaitHandle($false, [System.Threading.EventResetMode]::AutoReset, 'Local\BlueByeShow')

# ------------------------------------------------------------------ xaml ----

$xaml = @'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="BlueBye" Width="900" Height="632"
        WindowStyle="None" AllowsTransparency="True" Background="Transparent"
        WindowStartupLocation="CenterScreen" ResizeMode="NoResize"
        FontFamily="Microsoft YaHei UI, Segoe UI" UseLayoutRounding="True"
        TextOptions.TextFormattingMode="Display" SnapsToDevicePixels="True">
  <Window.Resources>
    <Style x:Key="FocusRing">
      <Setter Property="Control.Template">
        <Setter.Value>
          <ControlTemplate>
            <Border Brush="#2F6BE0" BorderThickness="2" CornerRadius="11" Margin="-3" Opacity="0.95"/>
          </ControlTemplate>
        </Setter.Value>
      </Setter>
    </Style>
    <Style x:Key="FlatIcon" TargetType="Button">
      <Setter Property="FocusVisualStyle" Value="{StaticResource FocusRing}"/>
      <Setter Property="Width" Value="30"/>
      <Setter Property="Height" Value="26"/>
      <Setter Property="Foreground" Value="#5E6A85"/>
      <Setter Property="FontSize" Value="12"/>
      <Setter Property="Cursor" Value="Hand"/>
      <Setter Property="Template">
        <Setter.Value>
          <ControlTemplate TargetType="Button">
            <Border x:Name="Bd" Background="Transparent" CornerRadius="8">
              <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/>
            </Border>
            <ControlTemplate.Triggers>
              <Trigger Property="IsMouseOver" Value="True">
                <Setter TargetName="Bd" Property="Background" Value="#FFFFFF"/>
                <Setter Property="Foreground" Value="#2C3450"/>
              </Trigger>
            </ControlTemplate.Triggers>
          </ControlTemplate>
        </Setter.Value>
      </Setter>
    </Style>

    <Style x:Key="Primary" TargetType="Button">
      <Setter Property="FocusVisualStyle" Value="{StaticResource FocusRing}"/>
      <Setter Property="Foreground" Value="#FFFFFF"/>
      <Setter Property="Background" Value="#2F6BE0"/>
      <Setter Property="FontSize" Value="12.5"/>
      <Setter Property="FontWeight" Value="SemiBold"/>
      <Setter Property="Padding" Value="18,0"/>
      <Setter Property="Height" Value="38"/>
      <Setter Property="Cursor" Value="Hand"/>
      <Setter Property="Template">
        <Setter.Value>
          <ControlTemplate TargetType="Button">
            <Border x:Name="Bd" Background="{TemplateBinding Background}" CornerRadius="11" Padding="{TemplateBinding Padding}">
              <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/>
            </Border>
            <ControlTemplate.Triggers>
              <Trigger Property="IsMouseOver" Value="True">
                <Setter TargetName="Bd" Property="Background" Value="#2A5FCB"/>
              </Trigger>
              <Trigger Property="IsPressed" Value="True">
                <Setter TargetName="Bd" Property="Background" Value="#234FA8"/>
              </Trigger>
            </ControlTemplate.Triggers>
          </ControlTemplate>
        </Setter.Value>
      </Setter>
    </Style>

    <Style x:Key="Secondary" TargetType="Button">
      <Setter Property="FocusVisualStyle" Value="{StaticResource FocusRing}"/>
      <Setter Property="Foreground" Value="#2C3450"/>
      <Setter Property="Background" Value="#FFFFFF"/>
      <Setter Property="FontSize" Value="12.5"/>
      <Setter Property="Height" Value="38"/>
      <Setter Property="Cursor" Value="Hand"/>
      <Setter Property="Template">
        <Setter.Value>
          <ControlTemplate TargetType="Button">
            <Border x:Name="Bd" Background="{TemplateBinding Background}" CornerRadius="11" Padding="{TemplateBinding Padding}"
                    BorderBrush="#DCE6F8" BorderThickness="1">
              <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/>
            </Border>
            <ControlTemplate.Triggers>
              <Trigger Property="IsMouseOver" Value="True">
                <Setter TargetName="Bd" Property="Background" Value="#F3F7FF"/>
                <Setter TargetName="Bd" Property="BorderBrush" Value="#BFD4F5"/>
              </Trigger>
              <Trigger Property="IsPressed" Value="True">
                <Setter TargetName="Bd" Property="Background" Value="#E8F0FE"/>
              </Trigger>
            </ControlTemplate.Triggers>
          </ControlTemplate>
        </Setter.Value>
      </Setter>
    </Style>

    <Style x:Key="Ghost" TargetType="Button">
      <Setter Property="FocusVisualStyle" Value="{StaticResource FocusRing}"/>
      <Setter Property="Foreground" Value="#6B7690"/>
      <Setter Property="Background" Value="Transparent"/>
      <Setter Property="FontSize" Value="12"/>
      <Setter Property="Padding" Value="8,0"/>
      <Setter Property="Height" Value="30"/>
      <Setter Property="Cursor" Value="Hand"/>
      <Setter Property="Template">
        <Setter.Value>
          <ControlTemplate TargetType="Button">
            <Border x:Name="Bd" Background="Transparent" CornerRadius="9" Padding="{TemplateBinding Padding}">
              <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/>
            </Border>
            <ControlTemplate.Triggers>
              <Trigger Property="IsMouseOver" Value="True">
                <Setter TargetName="Bd" Property="Background" Value="#E9F0FC"/>
                <Setter Property="Foreground" Value="#2F6BE0"/>
              </Trigger>
            </ControlTemplate.Triggers>
          </ControlTemplate>
        </Setter.Value>
      </Setter>
    </Style>

    <Style x:Key="Danger" TargetType="Button" BasedOn="{StaticResource Ghost}">
      <Setter Property="Foreground" Value="#B73A44"/>
    </Style>

    <Style x:Key="Stepper" TargetType="Button">
      <Setter Property="FocusVisualStyle" Value="{StaticResource FocusRing}"/>
      <Setter Property="Width" Value="28"/>
      <Setter Property="Height" Value="28"/>
      <Setter Property="Foreground" Value="#3D6FD0"/>
      <Setter Property="FontSize" Value="15"/>
      <Setter Property="Cursor" Value="Hand"/>
      <Setter Property="Template">
        <Setter.Value>
          <ControlTemplate TargetType="Button">
            <Border x:Name="Bd" Background="#EEF3FD" CornerRadius="9">
              <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/>
            </Border>
            <ControlTemplate.Triggers>
              <Trigger Property="IsMouseOver" Value="True">
                <Setter TargetName="Bd" Property="Background" Value="#DCE8FB"/>
              </Trigger>
              <Trigger Property="IsPressed" Value="True">
                <Setter TargetName="Bd" Property="Background" Value="#C9DAF7"/>
              </Trigger>
            </ControlTemplate.Triggers>
          </ControlTemplate>
        </Setter.Value>
      </Setter>
    </Style>

    <Style x:Key="Switch" TargetType="ToggleButton">
      <Setter Property="FocusVisualStyle" Value="{StaticResource FocusRing}"/>
      <Setter Property="Width" Value="44"/>
      <Setter Property="Height" Value="24"/>
      <Setter Property="Cursor" Value="Hand"/>
      <Setter Property="Template">
        <Setter.Value>
          <ControlTemplate TargetType="ToggleButton">
            <Grid>
              <Border x:Name="Track" CornerRadius="12" Background="#D9E1F0"/>
              <Ellipse x:Name="Knob" Width="18" Height="18" Fill="#FFFFFF"
                       HorizontalAlignment="Left" Margin="3,0,0,0"/>
            </Grid>
            <ControlTemplate.Triggers>
              <Trigger Property="IsChecked" Value="True">
                <Setter TargetName="Track" Property="Background" Value="#3F86F0"/>
                <Setter TargetName="Knob" Property="HorizontalAlignment" Value="Right"/>
                <Setter TargetName="Knob" Property="Margin" Value="0,0,3,0"/>
              </Trigger>
              <Trigger Property="IsMouseOver" Value="True">
                <Setter TargetName="Track" Property="Opacity" Value="0.9"/>
              </Trigger>
              <Trigger Property="IsEnabled" Value="False">
                <Setter TargetName="Track" Property="Opacity" Value="0.45"/>
                <Setter TargetName="Knob" Property="Opacity" Value="0.55"/>
              </Trigger>
            </ControlTemplate.Triggers>
          </ControlTemplate>
        </Setter.Value>
      </Setter>
    </Style>

    <Style x:Key="Card" TargetType="Border">
      <Setter Property="Background" Value="#FFFFFF"/>
      <Setter Property="BorderBrush" Value="#E6ECF8"/>
      <Setter Property="BorderThickness" Value="1"/>
      <Setter Property="CornerRadius" Value="16"/>
      <Setter Property="Padding" Value="18,16"/>
    </Style>

    <Style x:Key="RowLabel" TargetType="TextBlock">
      <Setter Property="Foreground" Value="#5E6A85"/>
      <Setter Property="FontSize" Value="12"/>
      <Setter Property="VerticalAlignment" Value="Center"/>
    </Style>

    <Style x:Key="RowValue" TargetType="TextBlock">
      <Setter Property="Foreground" Value="#2C3450"/>
      <Setter Property="FontSize" Value="12.5"/>
      <Setter Property="VerticalAlignment" Value="Center"/>
      <Setter Property="TextTrimming" Value="CharacterEllipsis"/>
    </Style>

    <Style x:Key="SectionTitle" TargetType="TextBlock">
      <Setter Property="Foreground" Value="#5E6A85"/>
      <Setter Property="FontSize" Value="11"/>
      <Setter Property="FontWeight" Value="SemiBold"/>
    </Style>

    <Style x:Key="Divider" TargetType="Border">
      <Setter Property="Height" Value="1"/>
      <Setter Property="Background" Value="#EEF2FA"/>
      <Setter Property="Margin" Value="0,7"/>
    </Style>
  </Window.Resources>

  <Grid>
    <Border CornerRadius="20" Background="#F5F7FC" Margin="12">
      <Border.Effect>
        <DropShadowEffect BlurRadius="30" ShadowDepth="4" Opacity="0.18" Color="#7C8DB5"/>
      </Border.Effect>
    </Border>

    <Border x:Name="Shell" CornerRadius="20" Background="#F5F7FC" Margin="12"
            BorderBrush="#E9EEF8" BorderThickness="1">
      <Grid>
        <Grid.RowDefinitions>
          <RowDefinition Height="156"/>
          <RowDefinition Height="*"/>
          <RowDefinition Height="74"/>
        </Grid.RowDefinitions>

        <Border x:Name="Header" Grid.Row="0" CornerRadius="19,19,0,0">
          <Border.Background>
            <LinearGradientBrush StartPoint="0,0" EndPoint="1,1">
              <GradientStop Color="#E4F1FF" Offset="0"/>
              <GradientStop Color="#E9E7FF" Offset="0.55"/>
              <GradientStop Color="#FFF1F7" Offset="1"/>
            </LinearGradientBrush>
          </Border.Background>
          <Grid>
            <Canvas IsHitTestVisible="False">
              <Ellipse Canvas.Left="640" Canvas.Top="-60" Width="240" Height="240" Fill="#FFFFFF" Opacity="0.26"/>
              <Ellipse Canvas.Left="800" Canvas.Top="86" Width="120" Height="120" Fill="#FFFFFF" Opacity="0.20"/>
              <Ellipse Canvas.Left="18" Canvas.Top="108" Width="90" Height="90" Fill="#FFFFFF" Opacity="0.16"/>
            </Canvas>

            <StackPanel Orientation="Horizontal" VerticalAlignment="Center" Margin="24,0,0,0">
              <Image x:Name="Mascot" Width="132" Height="132" VerticalAlignment="Center"
                     RenderOptions.BitmapScalingMode="HighQuality"/>
              <StackPanel Margin="8,0,0,0" VerticalAlignment="Center">
                <TextBlock Text="BlueBye" FontSize="27" FontWeight="Bold" Foreground="#2C3450"/>
                <TextBlock Text="离开工位自动暂停音乐，回来自动接上" FontSize="12.5" Foreground="#5E6A85" Margin="2,7,0,0"/>
              </StackPanel>
            </StackPanel>

            <StackPanel Orientation="Horizontal" HorizontalAlignment="Right" VerticalAlignment="Top" Margin="0,14,16,0">
              <Button x:Name="BtnMin" Content="—" Style="{StaticResource FlatIcon}"/>
              <Button x:Name="BtnClose" Content="✕" Style="{StaticResource FlatIcon}" Margin="6,0,0,0"/>
            </StackPanel>
          </Grid>
        </Border>

        <Grid Grid.Row="1" Margin="26,10,26,0">
          <Grid.ColumnDefinitions>
            <ColumnDefinition Width="352"/>
            <ColumnDefinition Width="20"/>
            <ColumnDefinition Width="*"/>
          </Grid.ColumnDefinitions>

          <StackPanel Grid.Column="0">
            <StackPanel Orientation="Horizontal" Margin="2,0,0,9">
              <Border Width="6" Height="6" CornerRadius="3" Background="#3F86F0" VerticalAlignment="Center"/>
              <TextBlock Text="实时状态" Style="{StaticResource SectionTitle}" Margin="7,0,0,0"/>
            </StackPanel>
            <Border Style="{StaticResource Card}">
              <StackPanel>
                <Grid Height="32">
                  <Grid.ColumnDefinitions>
                    <ColumnDefinition Width="18"/>
                    <ColumnDefinition Width="82"/>
                    <ColumnDefinition Width="*"/>
                  </Grid.ColumnDefinitions>
                  <Ellipse x:Name="DotBt" Grid.Column="0" Width="9" Height="9" Fill="#3F86F0" VerticalAlignment="Center" HorizontalAlignment="Left"/>
                  <TextBlock Grid.Column="1" Text="蓝牙" Style="{StaticResource RowLabel}"/>
                  <TextBlock x:Name="TxtBt" Grid.Column="2" Text="—" Style="{StaticResource RowValue}"/>
                </Grid>
                <Grid Height="32">
                  <Grid.ColumnDefinitions>
                    <ColumnDefinition Width="18"/>
                    <ColumnDefinition Width="82"/>
                    <ColumnDefinition Width="*"/>
                  </Grid.ColumnDefinitions>
                  <Ellipse x:Name="DotIdle" Grid.Column="0" Width="9" Height="9" Fill="#3F86F0" VerticalAlignment="Center" HorizontalAlignment="Left"/>
                  <TextBlock Grid.Column="1" Text="键鼠空闲" Style="{StaticResource RowLabel}"/>
                  <TextBlock x:Name="TxtIdle" Grid.Column="2" Text="—" Style="{StaticResource RowValue}"/>
                </Grid>
                <Grid Height="32">
                  <Grid.ColumnDefinitions>
                    <ColumnDefinition Width="18"/>
                    <ColumnDefinition Width="82"/>
                    <ColumnDefinition Width="*"/>
                  </Grid.ColumnDefinitions>
                  <Ellipse x:Name="DotState" Grid.Column="0" Width="9" Height="9" Fill="#3F86F0" VerticalAlignment="Center" HorizontalAlignment="Left"/>
                  <TextBlock Grid.Column="1" Text="守护状态" Style="{StaticResource RowLabel}"/>
                  <TextBlock x:Name="TxtState" Grid.Column="2" Text="—" Style="{StaticResource RowValue}"/>
                </Grid>
                <Grid Height="32">
                  <Grid.ColumnDefinitions>
                    <ColumnDefinition Width="18"/>
                    <ColumnDefinition Width="82"/>
                    <ColumnDefinition Width="*"/>
                  </Grid.ColumnDefinitions>
                  <Ellipse x:Name="DotPlaying" Grid.Column="0" Width="9" Height="9" Fill="#3F86F0" VerticalAlignment="Center" HorizontalAlignment="Left"/>
                  <TextBlock Grid.Column="1" Text="正在播放" Style="{StaticResource RowLabel}"/>
                  <TextBlock x:Name="TxtPlaying" Grid.Column="2" Text="—" Style="{StaticResource RowValue}"/>
                </Grid>
              </StackPanel>
            </Border>

            <Border Style="{StaticResource Card}" Margin="0,14,0,0">
              <StackPanel>
                <Button x:Name="BtnNight" Content="立即下班模式" Style="{StaticResource Secondary}" Margin="0,0,0,9"/>
                <Button x:Name="BtnRestore" Content="恢复蓝牙与播放" Style="{StaticResource Secondary}" Margin="0,0,0,9"/>
                <Button x:Name="BtnTest" Content="测试蓝牙开关" Style="{StaticResource Ghost}" Height="30"/>
              </StackPanel>
            </Border>
          </StackPanel>

          <StackPanel Grid.Column="2">
            <StackPanel Orientation="Horizontal" Margin="2,0,0,9">
              <Border Width="6" Height="6" CornerRadius="3" Background="#3F86F0" VerticalAlignment="Center"/>
              <TextBlock Text="行为设置" Style="{StaticResource SectionTitle}" Margin="7,0,0,0"/>
            </StackPanel>
            <Border Style="{StaticResource Card}">
              <StackPanel>
                <Grid Height="32">
                  <TextBlock Text="启用守护" FontSize="13" FontWeight="SemiBold" Foreground="#2C3450" VerticalAlignment="Center"/>
                  <ToggleButton x:Name="SwEnabled" AutomationProperties.Name="启用守护" Style="{StaticResource Switch}" HorizontalAlignment="Right" VerticalAlignment="Center"/>
                </Grid>

                <Border Style="{StaticResource Divider}"/>

                <Grid Height="38">
                  <TextBlock Text="空闲判定" Style="{StaticResource RowLabel}" VerticalAlignment="Center"/>
                  <StackPanel Orientation="Horizontal" HorizontalAlignment="Right" VerticalAlignment="Center">
                    <Button x:Name="IdleMinus" AutomationProperties.Name="减少空闲判定分钟数" Content="−" Style="{StaticResource Stepper}"/>
                    <TextBlock x:Name="IdleValue" Text="30" Width="46" TextAlignment="Center" FontSize="15" FontWeight="SemiBold" Foreground="#2C3450" VerticalAlignment="Center"/>
                    <Button x:Name="IdlePlus" AutomationProperties.Name="增加空闲判定分钟数" Content="+" Style="{StaticResource Stepper}"/>
                    <TextBlock Text="分钟" Style="{StaticResource RowLabel}" Margin="10,0,0,0" VerticalAlignment="Center"/>
                  </StackPanel>
                </Grid>

                <Border Style="{StaticResource Divider}"/>

                <Grid Height="38">
                  <TextBlock Text="夜间时段" Style="{StaticResource RowLabel}" VerticalAlignment="Center"/>
                  <StackPanel Orientation="Horizontal" HorizontalAlignment="Right" VerticalAlignment="Center">
                    <Button x:Name="StartMinus" AutomationProperties.Name="减少夜间起始小时" Content="−" Style="{StaticResource Stepper}"/>
                    <TextBlock x:Name="StartValue" Text="19" Width="34" TextAlignment="Center" FontSize="15" FontWeight="SemiBold" Foreground="#2C3450" VerticalAlignment="Center"/>
                    <Button x:Name="StartPlus" AutomationProperties.Name="增加夜间起始小时" Content="+" Style="{StaticResource Stepper}"/>
                    <TextBlock Text="点至" Style="{StaticResource RowLabel}" Margin="8,0,8,0" VerticalAlignment="Center"/>
                    <Button x:Name="EndMinus" AutomationProperties.Name="减少夜间结束小时" Content="−" Style="{StaticResource Stepper}"/>
                    <TextBlock x:Name="EndValue" Text="7" Width="34" TextAlignment="Center" FontSize="15" FontWeight="SemiBold" Foreground="#2C3450" VerticalAlignment="Center"/>
                    <Button x:Name="EndPlus" AutomationProperties.Name="增加夜间结束小时" Content="+" Style="{StaticResource Stepper}"/>
                    <TextBlock Text="点" Style="{StaticResource RowLabel}" Margin="8,0,0,0" VerticalAlignment="Center"/>
                  </StackPanel>
                </Grid>

                <Border Style="{StaticResource Divider}"/>

                <Grid Height="38">
                  <TextBlock Text="断蓝牙前缓冲" Style="{StaticResource RowLabel}" VerticalAlignment="Center"/>
                  <StackPanel Orientation="Horizontal" HorizontalAlignment="Right" VerticalAlignment="Center">
                    <Button x:Name="DelayMinus" AutomationProperties.Name="减少断蓝牙前缓冲分钟数" Content="−" Style="{StaticResource Stepper}"/>
                    <TextBlock x:Name="DelayValue" Text="10" Width="46" TextAlignment="Center" FontSize="15" FontWeight="SemiBold" Foreground="#2C3450" VerticalAlignment="Center"/>
                    <Button x:Name="DelayPlus" AutomationProperties.Name="增加断蓝牙前缓冲分钟数" Content="+" Style="{StaticResource Stepper}"/>
                    <TextBlock Text="分钟" Style="{StaticResource RowLabel}" Margin="10,0,0,0" VerticalAlignment="Center"/>
                  </StackPanel>
                </Grid>

                <Border Style="{StaticResource Divider}"/>

                <Grid Height="32">
                  <TextBlock Text="离开时暂停正在播放的音乐" FontSize="12.5" Foreground="#3A4463" VerticalAlignment="Center"/>
                  <ToggleButton x:Name="SwPause" AutomationProperties.Name="离开时暂停正在播放的音乐" Style="{StaticResource Switch}" HorizontalAlignment="Right" VerticalAlignment="Center"/>
                </Grid>
                <Grid Height="32">
                  <TextBlock Text="离开时断开蓝牙耳机" FontSize="12.5" Foreground="#3A4463" VerticalAlignment="Center"/>
                  <ToggleButton x:Name="SwRadio" AutomationProperties.Name="离开时断开蓝牙耳机" Style="{StaticResource Switch}" HorizontalAlignment="Right" VerticalAlignment="Center"/>
                </Grid>
                <Grid Height="32">
                  <TextBlock Text="通话或麦克风占用时跳过" FontSize="12.5" Foreground="#3A4463" VerticalAlignment="Center"/>
                  <ToggleButton x:Name="SwSkip" AutomationProperties.Name="通话或麦克风占用时跳过" Style="{StaticResource Switch}" HorizontalAlignment="Right" VerticalAlignment="Center"/>
                </Grid>
              </StackPanel>
            </Border>
          </StackPanel>
        </Grid>

        <Grid Grid.Row="2" Margin="26,0,26,18">
          <StackPanel Orientation="Horizontal" VerticalAlignment="Center">
            <ToggleButton x:Name="SwAuto" AutomationProperties.Name="开机自动启动" Style="{StaticResource Switch}" VerticalAlignment="Center"/>
            <TextBlock Text="开机自动启动" Style="{StaticResource RowLabel}" Margin="10,0,0,0" VerticalAlignment="Center"/>
            <TextBlock x:Name="TxtMsg" Text="就绪" FontSize="11.5" Foreground="#6B7690" Margin="20,0,0,0" MaxWidth="330"
                       TextTrimming="CharacterEllipsis" VerticalAlignment="Center"/>
          </StackPanel>
          <StackPanel Orientation="Horizontal" HorizontalAlignment="Right" VerticalAlignment="Center">
            <Button x:Name="BtnLog" Content="日志" Style="{StaticResource Ghost}" Margin="2,0"/>
            <Button x:Name="BtnDir" Content="文件夹" Style="{StaticResource Ghost}" Margin="2,0"/>
            <Button x:Name="BtnUninstall" Content="卸载" Style="{StaticResource Danger}" Margin="2,0"/>
            <Button x:Name="BtnSave" Content="保存设置" Style="{StaticResource Primary}" Margin="14,0,0,0"/>
          </StackPanel>
        </Grid>
      </Grid>
    </Border>
  </Grid>
</Window>
'@

$reader = New-Object System.Xml.XmlNodeReader ([xml]$xaml)
$win = [Windows.Markup.XamlReader]::Load($reader)

$icoPath = Join-Path $here 'bluebye.ico'
if (Test-Path $icoPath) {
  try { $win.Icon = [System.Windows.Media.Imaging.BitmapFrame]::Create([Uri]$icoPath) } catch { }
}

function E([string]$name) { return $win.FindName($name) }

$mascotPath = Join-Path $here 'mascot.png'
if (Test-Path $mascotPath) {
  try { (E 'Mascot').Source = [System.Windows.Media.Imaging.BitmapFrame]::Create([Uri]$mascotPath) } catch { }
}

$script:BrushCache = @{}
function Brush([string]$hex) {
  if (-not $script:BrushCache.ContainsKey($hex)) {
    $script:BrushCache[$hex] = New-Object System.Windows.Media.SolidColorBrush ([System.Windows.Media.ColorConverter]::ConvertFromString($hex))
  }
  return $script:BrushCache[$hex]
}

$script:CGreen = Brush '#22B573'
$script:CAmber = Brush '#E8931F'
$script:CRed = Brush '#B73A44'
$script:CGray = Brush '#B9C2D6'
$script:CAccent = Brush '#3F86F0'

function Set-Msg([string]$text, [string]$color = '#6B7690') {
  $tb = E 'TxtMsg'
  $tb.Text = $text
  $tb.Foreground = Brush $color
}

function Invoke-Engine([string]$mode, [int]$timeoutMs = 30000) {
  try {
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
    $psi.Arguments = '-NoProfile -ExecutionPolicy Bypass -File "' + $script:EnginePath + '" -Mode ' + $mode
    $psi.UseShellExecute = $false
    $psi.CreateNoWindow = $true
    $p = [System.Diagnostics.Process]::Start($psi)
    if (-not $p.WaitForExit($timeoutMs)) { try { $p.Kill() } catch { }; return -1 }
    return $p.ExitCode
  } catch {
    return -2
  }
}

function Format-Idle([int]$seconds) {
  if ($seconds -lt 60) { return "$seconds 秒" }
  if ($seconds -lt 3600) { return "$([int]($seconds / 60)) 分钟" }
  return "$([math]::Round($seconds / 3600, 1)) 小时"
}

function Update-Status {
  $cfg = Get-Cfg
  $st = Read-Status
  $idle = Get-IdleSeconds
  $running = Test-HostRunning
  $maxAge = [int]$cfg.TickSeconds * 3
  if ($maxAge -lt 60) { $maxAge = 60 }
  $fresh = Test-HeartbeatFresh $maxAge

  $bt = ''
  $phase = ''
  $playing = ''
  $enabled = [bool]$cfg.Enabled
  if ($st) {
    $bt = [string]$st.bt
    $phase = [string]$st.phase
    $playing = [string]$st.playing
    if ($null -ne $st.enabled) { $enabled = [bool]$st.enabled }
  }

  switch ($bt) {
    'On'      { (E 'TxtBt').Text = '已开启'; (E 'DotBt').Fill = $script:CGreen }
    'Off'     { (E 'TxtBt').Text = '已关闭（守护断开）'; (E 'DotBt').Fill = $script:CAmber }
    'Missing' { (E 'TxtBt').Text = '没有检测到蓝牙适配器'; (E 'DotBt').Fill = $script:CRed }
    default   { (E 'TxtBt').Text = '等待守护进程上报'; (E 'DotBt').Fill = $script:CGray }
  }

  (E 'TxtIdle').Text = Format-Idle $idle
  (E 'DotIdle').Fill = if ($idle -lt [int]$cfg.IdleMinutes * 60) { $script:CGreen } else { $script:CAmber }

  if (-not $running) {
    (E 'TxtState').Text = '守护进程未运行'
    (E 'DotState').Fill = $script:CRed
  } elseif (-not $fresh) {
    (E 'TxtState').Text = '守护无响应（心跳已停）'
    (E 'DotState').Fill = $script:CRed
  } elseif (-not $enabled) {
    (E 'TxtState').Text = '已暂停（总开关关闭）'
    (E 'DotState').Fill = $script:CGray
  } elseif ($phase -eq 'radiooff') {
    (E 'TxtState').Text = '已断开蓝牙，等你回来'
    (E 'DotState').Fill = $script:CAmber
  } elseif ($phase -eq 'paused') {
    (E 'TxtState').Text = '已暂停播放，稍后断开蓝牙'
    (E 'DotState').Fill = $script:CAmber
  } elseif ($idle -lt [int]$cfg.IdleMinutes * 60) {
    (E 'TxtState').Text = '值守中 · 检测到你在电脑前'
    (E 'DotState').Fill = $script:CGreen
  } else {
    (E 'TxtState').Text = '值守中'
    (E 'DotState').Fill = $script:CGreen
  }

  if ([string]::IsNullOrWhiteSpace($playing)) {
    (E 'TxtPlaying').Text = '—'
    (E 'DotPlaying').Fill = $script:CGray
  } else {
    (E 'TxtPlaying').Text = $playing
    (E 'DotPlaying').Fill = $script:CAccent
  }
}

function Step-Value([string]$name, [int]$delta, [int]$min, [int]$max, [int]$step) {
  $tb = E $name
  $v = 0
  [void][int]::TryParse($tb.Text, [ref]$v)
  $v = $v + ($delta * $step)
  if ($v -lt $min) { $v = $min }
  if ($v -gt $max) { $v = $max }
  $tb.Text = [string]$v
}

function Load-ConfigToUi {
  $cfg = Get-Cfg
  (E 'IdleValue').Text = [string][int]$cfg.IdleMinutes
  (E 'StartValue').Text = [string][int]$cfg.NightStartHour
  (E 'EndValue').Text = [string][int]$cfg.NightEndHour
  (E 'DelayValue').Text = [string][int]$cfg.RadioOffDelayMinutes
  (E 'SwEnabled').IsChecked = [bool]$cfg.Enabled
  (E 'SwPause').IsChecked = [bool]$cfg.PauseMedia
  (E 'SwRadio').IsChecked = [bool]$cfg.TurnOffBluetooth
  (E 'SwSkip').IsChecked = [bool]$cfg.SkipOnCallSession
  try {
    $t = Get-ScheduledTask -TaskName $script:TaskName -ErrorAction Stop
    (E 'SwAuto').IsChecked = ($t.State -ne 'Disabled')
  } catch {
    (E 'SwAuto').IsChecked = $false
    (E 'SwAuto').IsEnabled = $false
  }
}

# ---------------------------------------------------------------- events ----

$win.FindName('Header').Add_MouseLeftButtonDown({ try { $win.DragMove() } catch { } })
$win.FindName('BtnClose').Add_Click({ $win.Close() })
$win.FindName('BtnMin').Add_Click({ $win.WindowState = 'Minimized' })

$win.FindName('IdlePlus').Add_Click({ Step-Value 'IdleValue' 1 5 240 5 })
$win.FindName('IdleMinus').Add_Click({ Step-Value 'IdleValue' -1 5 240 5 })
$win.FindName('StartPlus').Add_Click({ Step-Value 'StartValue' 1 0 23 1 ; Test-NightWindow })
$win.FindName('StartMinus').Add_Click({ Step-Value 'StartValue' -1 0 23 1 ; Test-NightWindow })
$win.FindName('EndPlus').Add_Click({ Step-Value 'EndValue' 1 0 23 1 ; Test-NightWindow })
$win.FindName('EndMinus').Add_Click({ Step-Value 'EndValue' -1 0 23 1 ; Test-NightWindow })
$win.FindName('DelayPlus').Add_Click({ Step-Value 'DelayValue' 1 0 120 5 })
$win.FindName('DelayMinus').Add_Click({ Step-Value 'DelayValue' -1 0 120 5 })

function Test-NightWindow {
  $s = (E 'StartValue').Text
  $e = (E 'EndValue').Text
  if ($s -eq $e) { Set-Msg '起止小时相同 = 永不执行，请调整' '#E8931F' }
}

$win.FindName('BtnSave').Add_Click({
  try {
    $cfg = Get-Cfg
    $cfg.Enabled = [bool](E 'SwEnabled').IsChecked
    $cfg.PauseMedia = [bool](E 'SwPause').IsChecked
    $cfg.TurnOffBluetooth = [bool](E 'SwRadio').IsChecked
    $cfg.SkipOnCallSession = [bool](E 'SwSkip').IsChecked
    $cfg.IdleMinutes = [int](E 'IdleValue').Text
    $cfg.NightStartHour = [int](E 'StartValue').Text
    $cfg.NightEndHour = [int](E 'EndValue').Text
    $cfg.RadioOffDelayMinutes = [int](E 'DelayValue').Text
    Save-Cfg $cfg
    Set-Msg '已保存，30 秒内生效' '#22B573'
  } catch {
    Set-Msg ('保存失败：' + $_.Exception.Message) '#B73A44'
  }
})

$win.FindName('BtnNight').Add_Click({
  try {
    Set-Msg '正在暂停播放并断开蓝牙…' '#E8931F'
    [void](Invoke-Engine 'Night')
    Update-Status
    Set-Msg '已进入下班模式' '#E8931F'
  } catch {
    Set-Msg ('执行失败：' + $_.Exception.Message) '#B73A44'
  }
})

$win.FindName('BtnRestore').Add_Click({
  try {
    Set-Msg '正在恢复蓝牙…' '#E8931F'
    [void](Invoke-Engine 'Restore')
    [void](Invoke-Engine 'Resume')
    Update-Status
    Set-Msg '蓝牙已恢复' '#22B573'
  } catch {
    Set-Msg ('执行失败：' + $_.Exception.Message) '#B73A44'
  }
})

$win.FindName('BtnTest').Add_Click({
  try {
    $r = [System.Windows.MessageBox]::Show(
      "测试会真的关闭一次蓝牙再打开，大约 5 秒，耳机可能瞬间断连。`r`n`r`n要继续吗？",
      '测试蓝牙开关',
      [System.Windows.MessageBoxButton]::YesNo,
      [System.Windows.MessageBoxImage]::Question)
    if ($r -ne [System.Windows.MessageBoxResult]::Yes) { return }
    Set-Msg '正在测试蓝牙开关…' '#E8931F'
    [void](Invoke-Engine 'Test' 45000)
    Update-Status
    Set-Msg '测试完成：蓝牙可以正常开关' '#22B573'
  } catch {
    Set-Msg ('测试失败：' + $_.Exception.Message) '#B73A44'
  }
})

$win.FindName('BtnLog').Add_Click({
  try {
    $log = Join-Path $here 'bluebye.log'
    if (Test-Path $log) { Start-Process -FilePath 'notepad.exe' -ArgumentList ('"' + $log + '"') }
    else { Set-Msg '还没有日志文件' '#E8931F' }
  } catch { Set-Msg ('打不开日志：' + $_.Exception.Message) '#B73A44' }
})

$win.FindName('BtnDir').Add_Click({
  try { Start-Process -FilePath 'explorer.exe' -ArgumentList ('"' + $here + '"') }
  catch { Set-Msg ('打不开文件夹：' + $_.Exception.Message) '#B73A44' }
})

$win.FindName('SwAuto').Add_Click({
  try {
    $on = [bool](E 'SwAuto').IsChecked
    foreach ($n in $script:TaskNames) {
      if ($on) { Enable-ScheduledTask -TaskName $n -ErrorAction Stop | Out-Null }
      else { Disable-ScheduledTask -TaskName $n -ErrorAction Stop | Out-Null }
    }
    if ($on) { Set-Msg '已开启开机自启' '#22B573' } else { Set-Msg '已关闭开机自启（本次运行仍有效）' '#E8931F' }
  } catch {
    Set-Msg ('修改自启失败：' + $_.Exception.Message) '#B73A44'
  }
})

$win.FindName('BtnUninstall').Add_Click({
  try {
    $r = [System.Windows.MessageBox]::Show(
      "会停止守护、删除开机任务和程序文件。`r`n`r`n确定要卸载吗？",
      '卸载BlueBye',
      [System.Windows.MessageBoxButton]::YesNo,
      [System.Windows.MessageBoxImage]::Warning)
    if ($r -ne [System.Windows.MessageBoxResult]::Yes) { return }
    $un = Join-Path $here 'uninstall.ps1'
    if (Test-Path $un) {
      Start-Process -FilePath 'powershell.exe' -ArgumentList ('-NoProfile -ExecutionPolicy Bypass -File "' + $un + '" -Quiet') -WindowStyle Hidden -Wait
    }
    $win.Close()
  } catch {
    Set-Msg ('卸载失败：' + $_.Exception.Message) '#B73A44'
  }
})

# ---------------------------------------------------------------- tray ----

$script:Exiting = $false
$script:TrayIcon = $null

function Start-GuardIfStopped {
  # opening the window means "I want the guard on"; the tray "quit" leaves a
  # marker that also silences the watchdog, so remove it and start the task
  $flag = Join-Path $here 'stopped.flag'
  if (-not (Test-Path $flag)) { return }
  Remove-Item $flag -Force -ErrorAction SilentlyContinue
  foreach ($t in @('BlueBye-Host', 'BlueBye-Watchdog')) {
    Enable-ScheduledTask -TaskName $t -ErrorAction SilentlyContinue | Out-Null
  }
  Start-ScheduledTask -TaskName 'BlueBye-Host' -ErrorAction SilentlyContinue
}

function Show-MainWindow {
  try {
    Start-GuardIfStopped
    $win.ShowInTaskbar = $true
    $win.Show()
    $win.WindowState = 'Normal'
    $win.Activate()
  } catch { }
}

function Hide-MainWindow {
  try {
    $win.Hide()
    $win.ShowInTaskbar = $false
  } catch { }
}

function Exit-BlueBye {
  $script:Exiting = $true
  try { if ($script:TrayIcon) { $script:TrayIcon.Visible = $false; $script:TrayIcon.Dispose() } } catch { }
  try { $script:ShowEvent.Dispose() } catch { }
  try { $win.Close() } catch { }
  try { $script:App.Shutdown() } catch { }
}

function Set-AutoStart([bool]$on) {
  foreach ($n in $script:TaskNames) {
    if ($on) { Enable-ScheduledTask -TaskName $n -ErrorAction Stop | Out-Null }
    else { Disable-ScheduledTask -TaskName $n -ErrorAction Stop | Out-Null }
  }
}

if (-not $SelfTest) {
  Add-Type -AssemblyName System.Windows.Forms
  Add-Type -AssemblyName System.Drawing

  $ni = New-Object System.Windows.Forms.NotifyIcon
  try {
    $trayIco = Join-Path $here 'bluebye.ico'
    if (Test-Path $trayIco) { $ni.Icon = New-Object System.Drawing.Icon($trayIco) }
    else { $ni.Icon = [System.Drawing.SystemIcons]::Application }
  } catch { $ni.Icon = [System.Drawing.SystemIcons]::Application }
  $ni.Text = 'BlueBye'
  $ni.Visible = $true

  $menu = New-Object System.Windows.Forms.ContextMenuStrip
  $miOpen = $menu.Items.Add('打开设置')
  $miOpen.Add_Click({ Show-MainWindow })

  $miNight = $menu.Items.Add('立即下班模式')
  $miNight.Add_Click({
    try {
      Set-Msg '正在暂停播放并断开蓝牙…' '#E8931F'
      [void](Invoke-Engine 'Night')
      Update-Status
      Set-Msg '已进入下班模式' '#E8931F'
    } catch { }
  })

  $miRestore = $menu.Items.Add('恢复蓝牙与播放')
  $miRestore.Add_Click({
    try {
      [void](Invoke-Engine 'Restore')
      [void](Invoke-Engine 'Resume')
      Update-Status
      Set-Msg '蓝牙已恢复' '#22B573'
    } catch { }
  })

  [void]$menu.Items.Add('-')

  $miAuto = $menu.Items.Add('开机自动启动')
  $miAuto.CheckOnClick = $true
  try {
    $miAuto.Checked = ((Get-ScheduledTask -TaskName $script:TaskName -ErrorAction Stop).State -ne 'Disabled')
  } catch { }
  $miAuto.Add_Click({
    try {
      Set-AutoStart ([bool]$miAuto.Checked)
      if ($miAuto.Checked) { Set-Msg '已开启开机自启' '#22B573' } else { Set-Msg '已关闭开机自启' '#E8931F' }
    } catch { }
  })

  [void]$menu.Items.Add('-')

  $miExit = $menu.Items.Add('退出 BlueBye（停止守护）')
  $miExit.Add_Click({
    try { [void](Invoke-Engine 'Stop' 20000) } catch { }
    Exit-BlueBye
  })

  $ni.ContextMenuStrip = $menu
  $ni.Add_MouseDoubleClick({ Show-MainWindow })
  $script:TrayIcon = $ni
}

$win.Add_Closing({
  param($sender, $e)
  try { ('closing: exiting=' + $script:Exiting + ' type=' + $e.GetType().Name) | Add-Content -Path (Join-Path $here 'ui-debug.log') -Encoding UTF8 } catch { }
  if (-not $script:Exiting) {
    try { $e.Cancel = $true } catch { }
    Hide-MainWindow
    Set-Msg '已收进托盘，守护仍在后台运行' '#5E6A85'
  }
})

# ------------------------------------------------------------------- run ----

# opening the app again means "I want the guard on" (it may have been stopped
# from the tray menu, which leaves a marker so the watchdog stays quiet)
if (-not $SelfTest) { Start-GuardIfStopped }

Load-ConfigToUi
Update-Status

if ($SelfTest) {
  $w = [int]$win.Width
  $h = [int]$win.Height
  $win.Width = $w
  $win.Height = $h
  $root = $win.Content
  $root.Measure((New-Object System.Windows.Size($w, $h)))
  $root.Arrange((New-Object System.Windows.Rect(0, 0, $w, $h)))
  $root.UpdateLayout()

  $rtb = New-Object System.Windows.Media.Imaging.RenderTargetBitmap($w, $h, 96, 96, [System.Windows.Media.PixelFormats]::Pbgra32)
  $rtb.Render($root)
  $enc = New-Object System.Windows.Media.Imaging.PngBitmapEncoder
  $enc.Frames.Add([System.Windows.Media.Imaging.BitmapFrame]::Create($rtb))
  $fs = [System.IO.File]::Create((Join-Path $here 'ui-selftest.png'))
  $enc.Save($fs)
  $fs.Close()

  try {
    $lines = New-Object System.Collections.Generic.List[string]
    function Bounds([System.Windows.FrameworkElement]$fe) {
      try {
        $t = $fe.TransformToAncestor($root)
        $b = $t.TransformBounds((New-Object System.Windows.Rect(0, 0, $fe.ActualWidth, $fe.ActualHeight)))
        return ('@{0},{1} {2}x{3}' -f [int]$b.X, [int]$b.Y, [int]$b.Width, [int]$b.Height)
      } catch { return '@?' }
    }
    function Walk($el, [int]$d) {
      foreach ($ch in [System.Windows.LogicalTreeHelper]::GetChildren([System.Windows.DependencyObject]$el)) {
        if ($ch -isnot [System.Windows.DependencyObject]) { continue }
        $name = ''
        if ($ch -is [System.Windows.FrameworkElement]) { $name = $ch.Name }
        $txt = ''
        if ($ch -is [System.Windows.Controls.TextBlock]) { $txt = $ch.Text }
        elseif ($ch -is [System.Windows.Controls.ContentControl]) { $txt = [string]$ch.Content }
        if ($name -or $txt) {
          $g = ''
          if ($ch -is [System.Windows.FrameworkElement]) { $g = Bounds $ch }
          $lines.Add(('{0}{1} {2} {3} :: {4}' -f (' ' * $d), $ch.GetType().Name, $name, $g, $txt))
        }
        Walk $ch ($d + 2)
      }
    }
    Walk $root 0
    $lines | Set-Content -Path (Join-Path $here 'ui-selftest.txt') -Encoding UTF8
  } catch {
    ('tree dump failed: ' + $_.Exception.Message) | Set-Content -Path (Join-Path $here 'ui-selftest.txt') -Encoding UTF8
  }
  $win.Close()
  return
}

$timer = New-Object System.Windows.Threading.DispatcherTimer
$timer.Interval = [TimeSpan]::FromSeconds(1)
$timer.Add_Tick({
  try { Update-Status } catch { }
  try { if ($script:ShowEvent -and $script:ShowEvent.WaitOne(0)) { Show-MainWindow } } catch { }
  try { if ($script:TrayIcon) { $script:TrayIcon.Text = ('BlueBye · ' + (E 'TxtState').Text) } } catch { }
})
$timer.Start()

$win.Add_Closed({
  $timer.Stop()
  try { if ($script:TrayIcon) { $script:TrayIcon.Visible = $false; $script:TrayIcon.Dispose() } } catch { }
  try { $script:Mutex.ReleaseMutex() } catch { }
})

if ($Tray) {
  $win.ShowInTaskbar = $false
  $win.WindowState = 'Minimized'
}

# Application.Run (instead of ShowDialog) so hiding the window does not end the
# message loop - that is what makes "close to tray" possible.
$script:App = New-Object System.Windows.Application
$script:App.ShutdownMode = [System.Windows.ShutdownMode]::OnExplicitShutdown
[void]$script:App.Run($win)
