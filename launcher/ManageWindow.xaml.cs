using System;
using System.Collections.Generic;
using System.Globalization;
using System.IO;
using System.Linq;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Media;
using Microsoft.Win32;
using Vector.Launcher.Models;
using Vector.Launcher.Services;

namespace Vector.Launcher
{
    public partial class ManageWindow : Window
    {
        private readonly string _root;
        private readonly Manifest _original;
        private readonly List<Tool> _tools = new List<Tool>();
        private readonly List<string> _catOrder = new List<string>();
        private readonly Dictionary<string, string> _catNames = new Dictionary<string, string>();
        private readonly Dictionary<string, string> _catDescs = new Dictionary<string, string>();

        private Tool _current;
        private Button _currentButton;
        private bool _loading;

        public ManageWindow(string root, Manifest manifest)
        {
            InitializeComponent();
            _root = root;
            _original = manifest;

            foreach (var cat in manifest.Categories)
            {
                if (!_catNames.ContainsKey(cat.Id))
                {
                    _catOrder.Add(cat.Id);
                    _catNames[cat.Id] = cat.Name;
                    _catDescs[cat.Id] = cat.Description ?? "";
                }
                if (cat.Tools == null) continue;
                foreach (var t in cat.Tools)
                {
                    var c = Clone(t);
                    c.CategoryId = cat.Id;
                    _tools.Add(c);
                }
            }

            CatHint.Text = "Existing categories: " + string.Join(", ", _catOrder);
            BuildToolList();
            if (_tools.Count > 0)
                SelectTool(_tools.OrderBy(x => x.CategoryId).ThenBy(x => x.Name).First(), null);
        }

        private static Tool Clone(Tool t)
        {
            return new Tool
            {
                Id = t.Id,
                Name = t.Name,
                Description = t.Description,
                Type = t.Type,
                Path = t.Path,
                Plane = t.Plane,
                Baked = t.Baked,
                Console = t.Console,
                License = t.License,
                Status = t.Status,
                CategoryId = t.CategoryId,
                Source = t.Source == null ? null : new ToolSource { Url = t.Source.Url, Kind = t.Source.Kind }
            };
        }

        // Tool list

        private void BuildToolList()
        {
            ToolListPanel.Children.Clear();
            foreach (var tool in _tools.OrderBy(x => x.CategoryId).ThenBy(x => x.Name))
            {
                var local = tool;
                var btn = new Button { Style = (Style)FindResource("CategoryButton"), Height = 40 };
                btn.Content = BuildButtonContent(tool);
                btn.Click += (s, e) => SelectTool(local, btn);
                if (tool == _current) MarkSelected(btn, true);
                ToolListPanel.Children.Add(btn);
                if (tool == _current) _currentButton = btn;
            }
        }

        private Grid BuildButtonContent(Tool tool)
        {
            var grid = new Grid();
            grid.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
            grid.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });

            var name = new TextBlock
            {
                Text = string.IsNullOrEmpty(tool.Name) ? "(unnamed)" : tool.Name,
                Foreground = (Brush)FindResource("Text"),
                VerticalAlignment = VerticalAlignment.Center,
                TextTrimming = TextTrimming.CharacterEllipsis
            };
            var cat = new TextBlock
            {
                Text = tool.CategoryId,
                Opacity = 0.5,
                FontFamily = (FontFamily)FindResource("MonoFont"),
                FontSize = 10,
                VerticalAlignment = VerticalAlignment.Center
            };
            Grid.SetColumn(cat, 1);
            grid.Children.Add(name);
            grid.Children.Add(cat);
            return grid;
        }

        private void SelectTool(Tool tool, Button btn)
        {
            if (_currentButton != null) MarkSelected(_currentButton, false);

            _current = tool;
            if (btn == null) btn = FindButtonFor(tool);
            _currentButton = btn;
            if (btn != null) MarkSelected(btn, true);

            LoadEditor(tool);
        }

        private Button FindButtonFor(Tool tool)
        {
            int i = 0;
            foreach (var t in _tools.OrderBy(x => x.CategoryId).ThenBy(x => x.Name))
            {
                if (t == tool && i < ToolListPanel.Children.Count) return (Button)ToolListPanel.Children[i];
                i++;
            }
            return null;
        }

        private void MarkSelected(Button btn, bool on)
        {
            if (on)
            {
                btn.Background = (Brush)FindResource("SurfaceRaised");
                btn.BorderBrush = (Brush)FindResource("Accent");
            }
            else
            {
                btn.ClearValue(BackgroundProperty);
                btn.ClearValue(BorderBrushProperty);
            }
        }

        // Editor

        private void LoadEditor(Tool t)
        {
            _loading = true;
            TxtName.Text = t.Name ?? "";
            TxtDesc.Text = t.Description ?? "";
            TxtCategory.Text = t.CategoryId ?? "";
            TxtPath.Text = t.Path ?? "";
            TxtSource.Text = t.Source != null ? (t.Source.Url ?? "") : "";

            BuildSeg(SegType, new[] { "portable", "script", "builtin" }, t.Type, v => t.Type = v);
            BuildSeg(SegPlane, new[] { "both", "winpe", "live" }, t.Plane, v => t.Plane = v);
            BuildSeg(SegConsole, new[] { "No", "Yes" }, t.Console ? "Yes" : "No", v => t.Console = (v == "Yes"));
            BuildSeg(SegLicense, new[] { "oss", "freeware", "trial", "ours" }, t.License, v => t.License = v);
            BuildSeg(SegStatus, new[] { "none", "planned", "last-resort" },
                string.IsNullOrEmpty(t.Status) ? "none" : t.Status,
                v => t.Status = (v == "none" ? null : v));
            _loading = false;
        }

        private void ClearEditor()
        {
            _loading = true;
            TxtName.Text = "";
            TxtDesc.Text = "";
            TxtCategory.Text = "";
            TxtPath.Text = "";
            TxtSource.Text = "";
            SegType.Children.Clear();
            SegPlane.Children.Clear();
            SegConsole.Children.Clear();
            SegLicense.Children.Clear();
            SegStatus.Children.Clear();
            _loading = false;
        }

        private void BuildSeg(StackPanel container, string[] options, string current, Action<string> setter)
        {
            container.Children.Clear();
            foreach (var opt in options)
            {
                var b = new Button { Style = (Style)FindResource("FooterButton"), Content = opt };
                ApplySeg(b, string.Equals(opt, current, StringComparison.OrdinalIgnoreCase));
                var captured = opt;
                b.Click += (s, e) =>
                {
                    if (_current == null) return;
                    setter(captured);
                    foreach (Button sib in container.Children) ApplySeg(sib, sib == b);
                };
                container.Children.Add(b);
            }
        }

        private void ApplySeg(Button b, bool selected)
        {
            if (selected)
            {
                b.Background = (Brush)FindResource("SurfaceRaised");
                b.BorderBrush = (Brush)FindResource("Accent");
                b.Foreground = (Brush)FindResource("Accent");
            }
            else
            {
                b.ClearValue(BackgroundProperty);
                b.ClearValue(BorderBrushProperty);
                b.ClearValue(ForegroundProperty);
            }
        }

        // Field change handlers

        private void OnNameChanged(object sender, TextChangedEventArgs e)
        {
            if (_loading || _current == null) return;
            _current.Name = TxtName.Text;
            if (_currentButton != null) _currentButton.Content = BuildButtonContent(_current);
        }

        private void OnDescChanged(object sender, TextChangedEventArgs e)
        {
            if (_loading || _current == null) return;
            _current.Description = TxtDesc.Text;
        }

        private void OnCategoryChanged(object sender, TextChangedEventArgs e)
        {
            if (_loading || _current == null) return;
            _current.CategoryId = TxtCategory.Text;
            if (_currentButton != null) _currentButton.Content = BuildButtonContent(_current);
        }

        private void OnSourceChanged(object sender, TextChangedEventArgs e)
        {
            if (_loading || _current == null) return;
            var url = TxtSource.Text.Trim();
            if (url.Length == 0) { _current.Source = null; return; }
            if (_current.Source == null) _current.Source = new ToolSource { Kind = "page" };
            _current.Source.Url = url;
        }

        // Buttons

        private void OnBrowse(object sender, RoutedEventArgs e)
        {
            if (_current == null) return;
            var dlg = new OpenFileDialog
            {
                Title = "Select the tool file",
                Filter = "Programs (*.exe)|*.exe|Scripts (*.ps1)|*.ps1|All files (*.*)|*.*"
            };
            if (dlg.ShowDialog() != true) return;

            var src = System.IO.Path.GetFullPath(dlg.FileName);
            var rootFull = System.IO.Path.GetFullPath(_root);
            string rel;

            if (src.StartsWith(rootFull, StringComparison.OrdinalIgnoreCase))
            {
                rel = src.Substring(rootFull.Length).TrimStart('\\', '/').Replace('\\', '/');
                StatusText.Text = "Referenced in place.";
            }
            else
            {
                var catId = Norm(TxtCategory.Text);
                if (catId.Length == 0) catId = "utilities";
                var relFolder = _current.Type == "script" ? "scripts" : ("tools/" + catId);
                var destDir = System.IO.Path.Combine(_root, relFolder.Replace('/', '\\'));
                Directory.CreateDirectory(destDir);
                var destFile = System.IO.Path.Combine(destDir, System.IO.Path.GetFileName(src));
                File.Copy(src, destFile, true);
                rel = relFolder + "/" + System.IO.Path.GetFileName(src);
                StatusText.Text = "Copied into " + relFolder + "/";
            }

            _current.Path = rel;
            TxtPath.Text = rel;
        }

        private void OnAdd(object sender, RoutedEventArgs e)
        {
            var catId = _current != null ? _current.CategoryId : (_catOrder.Count > 0 ? _catOrder[0] : "utilities");
            var t = new Tool
            {
                Name = "New Tool",
                Description = "",
                Type = "portable",
                Plane = "both",
                Baked = false,
                Console = false,
                License = "freeware",
                Path = "",
                CategoryId = catId
            };
            _tools.Add(t);
            _current = t;
            _currentButton = null;
            BuildToolList();
            _currentButton = FindButtonFor(t);
            if (_currentButton != null) MarkSelected(_currentButton, true);
            LoadEditor(t);
            TxtName.Focus();
            TxtName.SelectAll();
        }

        private void OnRemove(object sender, RoutedEventArgs e)
        {
            if (_current == null) return;
            if (MessageBox.Show("Remove " + _current.Name + "?", "Manage Tools",
                MessageBoxButton.YesNo, MessageBoxImage.Question) != MessageBoxResult.Yes) return;

            _tools.Remove(_current);
            _current = null;
            _currentButton = null;
            BuildToolList();
            ClearEditor();
            if (_tools.Count > 0)
                SelectTool(_tools.OrderBy(x => x.CategoryId).ThenBy(x => x.Name).First(), null);
        }

        private void OnSave(object sender, RoutedEventArgs e)
        {
            try
            {
                var newManifest = new Manifest { Meta = _original.Meta };

                var order = new List<string>();
                foreach (var id in _catOrder)
                    if (_tools.Any(t => Norm(t.CategoryId) == id) && !order.Contains(id)) order.Add(id);
                foreach (var t in _tools)
                {
                    var id = Norm(t.CategoryId);
                    if (id.Length == 0) id = "utilities";
                    if (!order.Contains(id)) order.Add(id);
                }

                foreach (var id in order)
                {
                    var cat = new Category
                    {
                        Id = id,
                        Name = _catNames.ContainsKey(id) ? _catNames[id] : TitleCase(id),
                        Description = _catDescs.ContainsKey(id) ? _catDescs[id] : ""
                    };
                    foreach (var t in _tools.Where(x => (Norm(x.CategoryId).Length == 0 ? "utilities" : Norm(x.CategoryId)) == id))
                    {
                        if (string.IsNullOrEmpty(t.Id)) t.Id = Norm(t.Name);
                        cat.Tools.Add(t);
                    }
                    newManifest.Categories.Add(cat);
                }

                ManifestService.Save(_root, newManifest);
                DialogResult = true;
                Close();
            }
            catch (Exception ex)
            {
                MessageBox.Show("Could not save the manifest.\n\n" + ex.Message, "Manage Tools",
                    MessageBoxButton.OK, MessageBoxImage.Warning);
            }
        }

        private void OnClose(object sender, RoutedEventArgs e)
        {
            DialogResult = false;
            Close();
        }

        // Helpers

        private static string Norm(string s)
        {
            if (string.IsNullOrWhiteSpace(s)) return "";
            return s.Trim().ToLowerInvariant().Replace(' ', '-');
        }

        private static string TitleCase(string id)
        {
            var parts = id.Replace('-', ' ');
            return CultureInfo.CurrentCulture.TextInfo.ToTitleCase(parts);
        }
    }
}
