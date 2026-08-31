using System;
using System.Diagnostics;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Input;
using System.Windows.Media;
using Vector.Launcher.Models;
using Vector.Launcher.Services;

namespace Vector.Launcher
{
    public partial class MainWindow : Window
    {
        private string _root;
        private Manifest _manifest;
        private ShopConfig _shop;
        private PlaneEnv _env;
        private Button _selectedButton;

        public MainWindow()
        {
            InitializeComponent();

            // In WinPE the launcher is the shell: make it a borderless, full-screen
            // kiosk and block accidental close. The Reboot and Shutdown buttons power
            // the machine, so the window never needs to close itself.
            if (EnvironmentService.IsWinPE())
            {
                WindowStyle = WindowStyle.None;
                ResizeMode = ResizeMode.NoResize;
                WindowState = WindowState.Maximized;
                Topmost = true;
                Closing += (s, e) => e.Cancel = true;
            }

            try
            {
                Load();
            }
            catch (Exception ex)
            {
                ContentTitle.Text = "Startup error";
                ContentDesc.Text = ex.Message;
            }
        }

        private void Load()
        {
            _root = PathResolver.FindRoot();
            _env = EnvironmentService.Current;
            _manifest = ManifestService.LoadManifest(_root);
            _shop = ManifestService.LoadShop(_root);

            BrandTagline.Text = string.IsNullOrEmpty(_shop.Tagline) ? "Diagnostics and Repair" : _shop.Tagline;
            EnvLabel.Text = _env == PlaneEnv.WinPE ? "Environment: WinPE" : "Environment: Live Windows";
            BuildShopInfo();
            BuildSidebar();

            if (_manifest.Categories.Count > 0)
                SelectCategory(_manifest.Categories[0], (Button)SidebarPanel.Children[0]);
        }

        private void BuildShopInfo()
        {
            HeaderShopInfo.Children.Clear();
            if (!string.IsNullOrEmpty(_shop.ShopName))
                HeaderShopInfo.Children.Add(Line(_shop.ShopName, (Brush)FindResource("Text"), 14, FontWeights.SemiBold));
            if (!string.IsNullOrEmpty(_shop.Phone))
                HeaderShopInfo.Children.Add(Line(_shop.Phone, (Brush)FindResource("TextDim"), 12, FontWeights.Normal));
        }

        private static TextBlock Line(string text, Brush brush, double size, FontWeight weight)
        {
            return new TextBlock
            {
                Text = text,
                Foreground = brush,
                FontSize = size,
                FontWeight = weight,
                HorizontalAlignment = HorizontalAlignment.Right
            };
        }

        private void BuildSidebar()
        {
            SidebarPanel.Children.Clear();
            foreach (var cat in _manifest.Categories)
            {
                var localCat = cat;
                var btn = new Button { Style = (Style)FindResource("CategoryButton") };

                var grid = new Grid();
                grid.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
                grid.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });

                var name = new TextBlock { Text = cat.Name, VerticalAlignment = VerticalAlignment.Center };
                var count = new TextBlock
                {
                    Text = (cat.Tools != null ? cat.Tools.Count : 0).ToString(),
                    VerticalAlignment = VerticalAlignment.Center,
                    Opacity = 0.6,
                    FontFamily = (FontFamily)FindResource("MonoFont"),
                    FontSize = 11
                };
                Grid.SetColumn(count, 1);
                grid.Children.Add(name);
                grid.Children.Add(count);

                btn.Content = grid;
                btn.Click += (s, e) => SelectCategory(localCat, btn);
                SidebarPanel.Children.Add(btn);
            }
        }

        private void SelectCategory(Category cat, Button btn)
        {
            if (_selectedButton != null)
            {
                _selectedButton.ClearValue(BackgroundProperty);
                _selectedButton.ClearValue(BorderBrushProperty);
                _selectedButton.ClearValue(ForegroundProperty);
            }

            btn.Background = (Brush)FindResource("SurfaceRaised");
            btn.BorderBrush = (Brush)FindResource("Accent");
            btn.Foreground = (Brush)FindResource("Accent");
            _selectedButton = btn;

            ContentTitle.Text = cat.Name;
            ContentDesc.Text = cat.Description ?? "";
            RenderCards(cat);
        }

        private void RenderCards(Category cat)
        {
            CardsPanel.Children.Clear();
            if (cat.Tools == null) return;
            foreach (var tool in cat.Tools)
                CardsPanel.Children.Add(BuildCard(tool));
        }

        private Border BuildCard(Tool tool)
        {
            var state = ToolService.State(_root, tool, _env);
            var launchable = ToolService.IsLaunchable(state);

            var card = new Border
            {
                Width = 280,
                Margin = new Thickness(0, 0, 12, 12),
                Padding = new Thickness(14),
                CornerRadius = new CornerRadius(8),
                Background = (Brush)FindResource("Surface"),
                BorderBrush = (Brush)FindResource("Border"),
                BorderThickness = new Thickness(1)
            };

            var stack = new StackPanel();

            var top = new Grid();
            top.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
            top.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });

            var name = new TextBlock
            {
                Text = tool.Name,
                Foreground = (Brush)FindResource("Text"),
                FontSize = 14,
                FontWeight = FontWeights.SemiBold,
                TextTrimming = TextTrimming.CharacterEllipsis,
                VerticalAlignment = VerticalAlignment.Center
            };
            var pill = BuildPill(state);
            Grid.SetColumn(pill, 1);
            top.Children.Add(name);
            top.Children.Add(pill);

            var desc = new TextBlock
            {
                Text = tool.Description,
                Foreground = (Brush)FindResource("TextDim"),
                FontSize = 12,
                TextWrapping = TextWrapping.Wrap,
                Margin = new Thickness(0, 8, 0, 0)
            };

            stack.Children.Add(top);
            stack.Children.Add(desc);
            card.Child = stack;

            if (launchable)
            {
                card.Cursor = Cursors.Hand;
                var t = tool;
                card.MouseLeftButtonUp += (s, e) => LaunchTool(t);
                card.MouseEnter += (s, e) => card.BorderBrush = (Brush)FindResource("TextDim");
                card.MouseLeave += (s, e) => card.BorderBrush = (Brush)FindResource("Border");
            }
            else
            {
                card.Opacity = 0.55;
            }

            return card;
        }

        private Border BuildPill(ToolState state)
        {
            string label;
            string key;
            switch (state)
            {
                case ToolState.Ready: label = "Ready"; key = "Ready"; break;
                case ToolState.Builtin: label = "Built-in"; key = "Accent"; break;
                case ToolState.Planned: label = "Planned"; key = "Warning"; break;
                case ToolState.LiveOnly: label = "Live only"; key = "TextDim"; break;
                default: label = "Not Found"; key = "TextDim"; break;
            }

            var color = ((SolidColorBrush)FindResource(key)).Color;
            var tint = new SolidColorBrush(Color.FromArgb(0x22, color.R, color.G, color.B));

            return new Border
            {
                Background = tint,
                CornerRadius = new CornerRadius(4),
                Padding = new Thickness(7, 2, 7, 2),
                VerticalAlignment = VerticalAlignment.Center,
                Child = new TextBlock
                {
                    Text = label.ToUpperInvariant(),
                    Foreground = new SolidColorBrush(color),
                    FontSize = 10,
                    FontWeight = FontWeights.SemiBold
                }
            };
        }

        private void LaunchTool(Tool tool)
        {
            try
            {
                ToolService.Launch(_root, tool);
            }
            catch (Exception ex)
            {
                MessageBox.Show("Could not launch " + tool.Name + "\n\n" + ex.Message,
                    "Vector Toolset", MessageBoxButton.OK, MessageBoxImage.Warning);
            }
        }

        // Footer actions

        private void OnCmd(object sender, RoutedEventArgs e) { Run("cmd.exe", ""); }

        private void OnPowerShell(object sender, RoutedEventArgs e)
        {
            Run("powershell.exe", "-NoExit -ExecutionPolicy Bypass");
        }

        private void OnExplorer(object sender, RoutedEventArgs e) { Run("explorer.exe", "\"" + _root + "\""); }

        private void OnManage(object sender, RoutedEventArgs e)
        {
            try
            {
                var dlg = new ManageWindow(_root, _manifest) { Owner = this };
                if (dlg.ShowDialog() == true) ReloadManifest();
            }
            catch (Exception ex)
            {
                MessageBox.Show("Could not open Manage Tools.\n\n" + ex.Message, "Vector Toolset",
                    MessageBoxButton.OK, MessageBoxImage.Warning);
            }
        }

        private void ReloadManifest()
        {
            _manifest = ManifestService.LoadManifest(_root);
            _selectedButton = null;
            BuildSidebar();
            if (_manifest.Categories.Count > 0)
            {
                SelectCategory(_manifest.Categories[0], (Button)SidebarPanel.Children[0]);
            }
            else
            {
                CardsPanel.Children.Clear();
                ContentTitle.Text = "";
                ContentDesc.Text = "";
            }
        }

        private void OnReboot(object sender, RoutedEventArgs e)
        {
            var live = _env == PlaneEnv.Live;
            var msg = live ? "Reboot THIS computer now? Any unsaved work will be lost." : "Reboot?";
            // WinPE has no working shutdown.exe path; wpeutil is the supported way to
            // cycle power there. On live Windows use shutdown.exe without /f so apps
            // can veto a bad reboot.
            if (Confirm(msg))
            {
                if (live) Run("shutdown.exe", "/r /t 3");
                else Run("wpeutil.exe", "reboot");
            }
        }

        private void OnShutdown(object sender, RoutedEventArgs e)
        {
            var live = _env == PlaneEnv.Live;
            var msg = live ? "Shut down THIS computer now? Any unsaved work will be lost." : "Shut down?";
            if (Confirm(msg))
            {
                if (live) Run("shutdown.exe", "/s /t 3");
                else Run("wpeutil.exe", "shutdown");
            }
        }

        private static bool Confirm(string message)
        {
            return MessageBox.Show(message, "Vector Toolset", MessageBoxButton.YesNo, MessageBoxImage.Question)
                == MessageBoxResult.Yes;
        }

        private void Run(string exe, string args)
        {
            try
            {
                Process.Start(new ProcessStartInfo { FileName = exe, Arguments = args, UseShellExecute = true });
            }
            catch (Exception ex)
            {
                MessageBox.Show("Could not run " + exe + "\n\n" + ex.Message,
                    "Vector Toolset", MessageBoxButton.OK, MessageBoxImage.Warning);
            }
        }
    }
}
