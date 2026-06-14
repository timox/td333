{
	"patcher" : 	{
		"fileversion" : 1,
		"appversion" : 		{
			"major" : 8,
			"minor" : 5,
			"revision" : 0,
			"architecture" : "x64",
			"modernui" : 1
		}
,
		"classnamespace" : "box",
		"rect" : [ 80.0, 90.0, 640.0, 420.0 ],
		"bglocked" : 0,
		"openinpresentation" : 0,
		"default_fontsize" : 12.0,
		"default_fontface" : 0,
		"default_fontname" : "Arial",
		"gridonopen" : 1,
		"gridsize" : [ 15.0, 15.0 ],
		"boxes" : [
			{ "box" : { "id" : "obj-js", "maxclass" : "newobj", "text" : "js td3_live.js", "numinlets" : 1, "numoutlets" : 2, "outlettype" : [ "", "" ], "patching_rect" : [ 40.0, 250.0, 110.0, 22.0 ] } },
			{ "box" : { "id" : "obj-notein", "maxclass" : "newobj", "text" : "notein", "numinlets" : 1, "numoutlets" : 3, "outlettype" : [ "int", "int", "int" ], "patching_rect" : [ 40.0, 160.0, 50.0, 22.0 ] } },
			{ "box" : { "id" : "obj-pack", "maxclass" : "newobj", "text" : "pack 0 0", "numinlets" : 2, "numoutlets" : 1, "outlettype" : [ "" ], "patching_rect" : [ 40.0, 190.0, 60.0, 22.0 ] } },
			{ "box" : { "id" : "obj-pnote", "maxclass" : "newobj", "text" : "prepend note", "numinlets" : 1, "numoutlets" : 1, "outlettype" : [ "" ], "patching_rect" : [ 40.0, 220.0, 80.0, 22.0 ] } },
			{ "box" : { "id" : "obj-midiout", "maxclass" : "newobj", "text" : "midiout", "numinlets" : 1, "numoutlets" : 0, "patching_rect" : [ 40.0, 360.0, 56.0, 22.0 ] } },

			{ "box" : { "id" : "obj-cut", "maxclass" : "dial", "size" : 128, "numinlets" : 1, "numoutlets" : 1, "outlettype" : [ "float" ], "patching_rect" : [ 470.0, 50.0, 50.0, 50.0 ] } },
			{ "box" : { "id" : "obj-cutlbl", "maxclass" : "comment", "text" : "cutoff (CC74)", "numinlets" : 1, "numoutlets" : 0, "patching_rect" : [ 460.0, 102.0, 90.0, 20.0 ] } },
			{ "box" : { "id" : "obj-pcut", "maxclass" : "newobj", "text" : "prepend cutoff", "numinlets" : 1, "numoutlets" : 1, "outlettype" : [ "" ], "patching_rect" : [ 470.0, 130.0, 90.0, 22.0 ] } },

			{ "box" : { "id" : "obj-ch", "maxclass" : "number", "minimum" : 1, "maximum" : 16, "numinlets" : 1, "numoutlets" : 2, "outlettype" : [ "int", "bang" ], "patching_rect" : [ 40.0, 50.0, 50.0, 22.0 ] } },
			{ "box" : { "id" : "obj-chl", "maxclass" : "comment", "text" : "MIDI channel", "numinlets" : 1, "numoutlets" : 0, "patching_rect" : [ 95.0, 52.0, 90.0, 20.0 ] } },
			{ "box" : { "id" : "obj-pch", "maxclass" : "newobj", "text" : "prepend channel", "numinlets" : 1, "numoutlets" : 1, "outlettype" : [ "" ], "patching_rect" : [ 40.0, 80.0, 100.0, 22.0 ] } },

			{ "box" : { "id" : "obj-th", "maxclass" : "number", "minimum" : 1, "maximum" : 127, "numinlets" : 1, "numoutlets" : 2, "outlettype" : [ "int", "bang" ], "patching_rect" : [ 200.0, 50.0, 50.0, 22.0 ] } },
			{ "box" : { "id" : "obj-thl", "maxclass" : "comment", "text" : "accent threshold (vel)", "numinlets" : 1, "numoutlets" : 0, "patching_rect" : [ 255.0, 52.0, 140.0, 20.0 ] } },
			{ "box" : { "id" : "obj-pth", "maxclass" : "newobj", "text" : "prepend threshold", "numinlets" : 1, "numoutlets" : 1, "outlettype" : [ "" ], "patching_rect" : [ 200.0, 80.0, 110.0, 22.0 ] } },

			{ "box" : { "id" : "obj-nv", "maxclass" : "number", "minimum" : 1, "maximum" : 127, "numinlets" : 1, "numoutlets" : 2, "outlettype" : [ "int", "bang" ], "patching_rect" : [ 200.0, 110.0, 50.0, 22.0 ] } },
			{ "box" : { "id" : "obj-nvl", "maxclass" : "comment", "text" : "normal vel", "numinlets" : 1, "numoutlets" : 0, "patching_rect" : [ 255.0, 112.0, 80.0, 20.0 ] } },
			{ "box" : { "id" : "obj-pnv", "maxclass" : "newobj", "text" : "prepend normalvel", "numinlets" : 1, "numoutlets" : 1, "outlettype" : [ "" ], "patching_rect" : [ 200.0, 138.0, 115.0, 22.0 ] } },

			{ "box" : { "id" : "obj-av", "maxclass" : "number", "minimum" : 1, "maximum" : 127, "numinlets" : 1, "numoutlets" : 2, "outlettype" : [ "int", "bang" ], "patching_rect" : [ 340.0, 110.0, 50.0, 22.0 ] } },
			{ "box" : { "id" : "obj-avl", "maxclass" : "comment", "text" : "accent vel", "numinlets" : 1, "numoutlets" : 0, "patching_rect" : [ 395.0, 112.0, 80.0, 20.0 ] } },
			{ "box" : { "id" : "obj-pav", "maxclass" : "newobj", "text" : "prepend accentvel", "numinlets" : 1, "numoutlets" : 1, "outlettype" : [ "" ], "patching_rect" : [ 340.0, 138.0, 115.0, 22.0 ] } },

			{ "box" : { "id" : "obj-sm", "maxclass" : "number", "minimum" : 0, "maximum" : 50, "numinlets" : 1, "numoutlets" : 2, "outlettype" : [ "int", "bang" ], "patching_rect" : [ 340.0, 50.0, 50.0, 22.0 ] } },
			{ "box" : { "id" : "obj-sml", "maxclass" : "comment", "text" : "slide overlap (ms)", "numinlets" : 1, "numoutlets" : 0, "patching_rect" : [ 395.0, 52.0, 120.0, 20.0 ] } },
			{ "box" : { "id" : "obj-psm", "maxclass" : "newobj", "text" : "prepend slidems", "numinlets" : 1, "numoutlets" : 1, "outlettype" : [ "" ], "patching_rect" : [ 340.0, 80.0, 100.0, 22.0 ] } },

			{ "box" : { "id" : "obj-panic", "maxclass" : "message", "text" : "panic", "numinlets" : 2, "numoutlets" : 1, "outlettype" : [ "" ], "patching_rect" : [ 160.0, 250.0, 50.0, 22.0 ] } },

			{ "box" : { "id" : "obj-stat", "maxclass" : "comment", "text" : "status", "numinlets" : 1, "numoutlets" : 0, "patching_rect" : [ 40.0, 320.0, 400.0, 20.0 ] } },
			{ "box" : { "id" : "obj-title", "maxclass" : "comment", "text" : "TD-3 Live (Max for Live) — accent / slide / cutoff, no SysEx", "numinlets" : 1, "numoutlets" : 0, "patching_rect" : [ 40.0, 12.0, 450.0, 20.0 ] } }
		],
		"lines" : [
			{ "patchline" : { "source" : [ "obj-notein", 0 ], "destination" : [ "obj-pack", 0 ] } },
			{ "patchline" : { "source" : [ "obj-notein", 1 ], "destination" : [ "obj-pack", 1 ] } },
			{ "patchline" : { "source" : [ "obj-pack", 0 ], "destination" : [ "obj-pnote", 0 ] } },
			{ "patchline" : { "source" : [ "obj-pnote", 0 ], "destination" : [ "obj-js", 0 ] } },
			{ "patchline" : { "source" : [ "obj-js", 0 ], "destination" : [ "obj-midiout", 0 ] } },
			{ "patchline" : { "source" : [ "obj-js", 1 ], "destination" : [ "obj-stat", 0 ] } },

			{ "patchline" : { "source" : [ "obj-cut", 0 ], "destination" : [ "obj-pcut", 0 ] } },
			{ "patchline" : { "source" : [ "obj-pcut", 0 ], "destination" : [ "obj-js", 0 ] } },
			{ "patchline" : { "source" : [ "obj-ch", 0 ], "destination" : [ "obj-pch", 0 ] } },
			{ "patchline" : { "source" : [ "obj-pch", 0 ], "destination" : [ "obj-js", 0 ] } },
			{ "patchline" : { "source" : [ "obj-th", 0 ], "destination" : [ "obj-pth", 0 ] } },
			{ "patchline" : { "source" : [ "obj-pth", 0 ], "destination" : [ "obj-js", 0 ] } },
			{ "patchline" : { "source" : [ "obj-nv", 0 ], "destination" : [ "obj-pnv", 0 ] } },
			{ "patchline" : { "source" : [ "obj-pnv", 0 ], "destination" : [ "obj-js", 0 ] } },
			{ "patchline" : { "source" : [ "obj-av", 0 ], "destination" : [ "obj-pav", 0 ] } },
			{ "patchline" : { "source" : [ "obj-pav", 0 ], "destination" : [ "obj-js", 0 ] } },
			{ "patchline" : { "source" : [ "obj-sm", 0 ], "destination" : [ "obj-psm", 0 ] } },
			{ "patchline" : { "source" : [ "obj-psm", 0 ], "destination" : [ "obj-js", 0 ] } },
			{ "patchline" : { "source" : [ "obj-panic", 0 ], "destination" : [ "obj-js", 0 ] } }
		]
	}
}
