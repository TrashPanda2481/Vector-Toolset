using System.Collections.Generic;
using Newtonsoft.Json;
using Newtonsoft.Json.Linq;

namespace Vector.Launcher.Models
{
    public class Manifest
    {
        public JObject Meta { get; set; }
        public List<Category> Categories { get; set; } = new List<Category>();
    }

    public class Category
    {
        public string Id { get; set; }
        public string Name { get; set; }
        public string Description { get; set; }
        public List<Tool> Tools { get; set; } = new List<Tool>();
    }

    public class Tool
    {
        public string Id { get; set; }
        public string Name { get; set; }
        public string Description { get; set; }
        public string Type { get; set; }       // script | builtin | portable
        public string Path { get; set; }        // relative to the stick root
        public string Plane { get; set; }       // winpe | live | both
        public bool Baked { get; set; }
        public bool Console { get; set; }
        public string License { get; set; }
        public string Status { get; set; }      // optional: planned | last-resort
        public ToolSource Source { get; set; }

        // Editing helper only, not serialized. Holds the parent category id.
        [JsonIgnore]
        public string CategoryId { get; set; }
    }

    public class ToolSource
    {
        public string Url { get; set; }
        public string Kind { get; set; }
    }

    public class ShopConfig
    {
        public string Product { get; set; }
        public string ShopName { get; set; }
        public string Tagline { get; set; }
        public string TechName { get; set; }
        public string Phone { get; set; }
        public string Website { get; set; }
    }
}
