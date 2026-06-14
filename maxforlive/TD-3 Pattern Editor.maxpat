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
		"rect" : [ 80.0, 90.0, 720.0, 540.0 ],
		"bglocked" : 0,
		"openinpresentation" : 0,
		"default_fontsize" : 12.0,
		"default_fontface" : 0,
		"default_fontname" : "Arial",
		"gridonopen" : 1,
		"gridsize" : [ 15.0, 15.0 ],
		"boxes" : [
			{ "box" : { "id" : "obj-js", "maxclass" : "newobj", "text" : "js td3_device.js", "numinlets" : 2, "numoutlets" : 4, "outlettype" : [ "", "", "", "" ], "patching_rect" : [ 40.0, 320.0, 130.0, 22.0 ] } },
			{ "box" : { "id" : "obj-midiin", "maxclass" : "newobj", "text" : "midiin", "numinlets" : 1, "numoutlets" : 1, "outlettype" : [ "int" ], "patching_rect" : [ 360.0, 270.0, 50.0, 22.0 ] } },
			{ "box" : { "id" : "obj-midiout", "maxclass" : "newobj", "text" : "midiout", "numinlets" : 1, "numoutlets" : 0, "patching_rect" : [ 40.0, 470.0, 56.0, 22.0 ] } },

			{ "box" : { "id" : "obj-grp", "maxclass" : "umenu", "items" : "I,II,III,IV", "numinlets" : 1, "numoutlets" : 3, "outlettype" : [ "int", "", "menu" ], "parameter_enable" : 0, "patching_rect" : [ 40.0, 40.0, 60.0, 22.0 ] } },
			{ "box" : { "id" : "obj-pat", "maxclass" : "umenu", "items" : "1A,2A,3A,4A,5A,6A,7A,8A,1B,2B,3B,4B,5B,6B,7B,8B", "numinlets" : 1, "numoutlets" : 3, "outlettype" : [ "int", "", "menu" ], "parameter_enable" : 0, "patching_rect" : [ 110.0, 40.0, 60.0, 22.0 ] } },
			{ "box" : { "id" : "obj-trip", "maxclass" : "toggle", "numinlets" : 1, "numoutlets" : 1, "outlettype" : [ "int" ], "patching_rect" : [ 190.0, 40.0, 22.0, 22.0 ] } },
			{ "box" : { "id" : "obj-triplbl", "maxclass" : "comment", "text" : "triplet", "numinlets" : 1, "numoutlets" : 0, "patching_rect" : [ 215.0, 42.0, 45.0, 20.0 ] } },
			{ "box" : { "id" : "obj-sc", "maxclass" : "number", "minimum" : 1, "maximum" : 16, "numinlets" : 1, "numoutlets" : 2, "outlettype" : [ "int", "bang" ], "patching_rect" : [ 270.0, 40.0, 50.0, 22.0 ] } },
			{ "box" : { "id" : "obj-sclbl", "maxclass" : "comment", "text" : "steps", "numinlets" : 1, "numoutlets" : 0, "patching_rect" : [ 322.0, 42.0, 45.0, 20.0 ] } },
			{ "box" : { "id" : "obj-oct", "maxclass" : "number", "minimum" : -2, "maximum" : 2, "numinlets" : 1, "numoutlets" : 2, "outlettype" : [ "int", "bang" ], "patching_rect" : [ 380.0, 40.0, 50.0, 22.0 ] } },
			{ "box" : { "id" : "obj-octlbl", "maxclass" : "comment", "text" : "octave shift", "numinlets" : 1, "numoutlets" : 0, "patching_rect" : [ 432.0, 42.0, 80.0, 20.0 ] } },

			{ "box" : { "id" : "obj-mtx", "maxclass" : "matrixctrl", "rows" : 3, "columns" : 16, "numinlets" : 1, "numoutlets" : 2, "outlettype" : [ "list", "list" ], "patching_rect" : [ 40.0, 90.0, 480.0, 60.0 ] } },
			{ "box" : { "id" : "obj-mtxlbl", "maxclass" : "comment", "text" : "rows: active / accent / slide", "numinlets" : 1, "numoutlets" : 0, "patching_rect" : [ 530.0, 110.0, 170.0, 20.0 ] } },
			{ "box" : { "id" : "obj-pitch", "maxclass" : "multislider", "size" : 16, "candicane2" : [ 0.4, 0.6, 1.0, 1.0 ], "setminmax" : [ 0.0, 36.0 ], "contdata" : 0, "numinlets" : 1, "numoutlets" : 2, "outlettype" : [ "", "" ], "patching_rect" : [ 40.0, 170.0, 480.0, 80.0 ] } },
			{ "box" : { "id" : "obj-pitchlbl", "maxclass" : "comment", "text" : "pitch 0..36 = C1..C4", "numinlets" : 1, "numoutlets" : 0, "patching_rect" : [ 530.0, 200.0, 150.0, 20.0 ] } },

			{ "box" : { "id" : "obj-write", "maxclass" : "message", "text" : "write", "numinlets" : 2, "numoutlets" : 1, "outlettype" : [ "" ], "patching_rect" : [ 40.0, 270.0, 50.0, 22.0 ] } },
			{ "box" : { "id" : "obj-read", "maxclass" : "message", "text" : "request", "numinlets" : 2, "numoutlets" : 1, "outlettype" : [ "" ], "patching_rect" : [ 100.0, 270.0, 60.0, 22.0 ] } },
			{ "box" : { "id" : "obj-clear", "maxclass" : "message", "text" : "clear", "numinlets" : 2, "numoutlets" : 1, "outlettype" : [ "" ], "patching_rect" : [ 170.0, 270.0, 50.0, 22.0 ] } },
			{ "box" : { "id" : "obj-dump", "maxclass" : "message", "text" : "dump", "numinlets" : 2, "numoutlets" : 1, "outlettype" : [ "" ], "patching_rect" : [ 230.0, 270.0, 50.0, 22.0 ] } },

			{ "box" : { "id" : "obj-pg", "maxclass" : "newobj", "text" : "prepend group", "numinlets" : 1, "numoutlets" : 1, "outlettype" : [ "" ], "patching_rect" : [ 40.0, 70.0, 90.0, 22.0 ] } },
			{ "box" : { "id" : "obj-pp", "maxclass" : "newobj", "text" : "prepend pattern", "numinlets" : 1, "numoutlets" : 1, "outlettype" : [ "" ], "patching_rect" : [ 110.0, 70.0, 95.0, 22.0 ] } },
			{ "box" : { "id" : "obj-pt", "maxclass" : "newobj", "text" : "prepend triplet", "numinlets" : 1, "numoutlets" : 1, "outlettype" : [ "" ], "patching_rect" : [ 190.0, 240.0, 90.0, 22.0 ] } },
			{ "box" : { "id" : "obj-psc", "maxclass" : "newobj", "text" : "prepend stepcount", "numinlets" : 1, "numoutlets" : 1, "outlettype" : [ "" ], "patching_rect" : [ 270.0, 240.0, 110.0, 22.0 ] } },
			{ "box" : { "id" : "obj-poc", "maxclass" : "newobj", "text" : "prepend octave", "numinlets" : 1, "numoutlets" : 1, "outlettype" : [ "" ], "patching_rect" : [ 390.0, 240.0, 90.0, 22.0 ] } },
			{ "box" : { "id" : "obj-pc", "maxclass" : "newobj", "text" : "prepend cell", "numinlets" : 1, "numoutlets" : 1, "outlettype" : [ "" ], "patching_rect" : [ 40.0, 155.0, 80.0, 22.0 ] } },
			{ "box" : { "id" : "obj-ppi", "maxclass" : "newobj", "text" : "prepend pitches", "numinlets" : 1, "numoutlets" : 1, "outlettype" : [ "" ], "patching_rect" : [ 200.0, 255.0, 95.0, 22.0 ] } },

			{ "box" : { "id" : "obj-route", "maxclass" : "newobj", "text" : "route group pattern triplet stepcount matrix sliders", "numinlets" : 1, "numoutlets" : 7, "outlettype" : [ "", "", "", "", "", "", "" ], "patching_rect" : [ 200.0, 360.0, 320.0, 22.0 ] } },
			{ "box" : { "id" : "obj-setg", "maxclass" : "newobj", "text" : "prepend set", "numinlets" : 1, "numoutlets" : 1, "outlettype" : [ "" ], "patching_rect" : [ 200.0, 400.0, 70.0, 22.0 ] } },
			{ "box" : { "id" : "obj-setp", "maxclass" : "newobj", "text" : "prepend set", "numinlets" : 1, "numoutlets" : 1, "outlettype" : [ "" ], "patching_rect" : [ 275.0, 400.0, 70.0, 22.0 ] } },
			{ "box" : { "id" : "obj-sett", "maxclass" : "newobj", "text" : "prepend set", "numinlets" : 1, "numoutlets" : 1, "outlettype" : [ "" ], "patching_rect" : [ 350.0, 400.0, 70.0, 22.0 ] } },
			{ "box" : { "id" : "obj-sets", "maxclass" : "newobj", "text" : "prepend set", "numinlets" : 1, "numoutlets" : 1, "outlettype" : [ "" ], "patching_rect" : [ 425.0, 400.0, 70.0, 22.0 ] } },

			{ "box" : { "id" : "obj-hex", "maxclass" : "comment", "text" : "(SysEx hex appears here)", "numinlets" : 1, "numoutlets" : 0, "patching_rect" : [ 40.0, 500.0, 660.0, 20.0 ] } },
			{ "box" : { "id" : "obj-stat", "maxclass" : "comment", "text" : "status", "numinlets" : 1, "numoutlets" : 0, "patching_rect" : [ 300.0, 470.0, 400.0, 20.0 ] } },
			{ "box" : { "id" : "obj-title", "maxclass" : "comment", "text" : "TD-3 Pattern Editor (Max for Live) — Behringer TD-3 / TD-3-MO", "numinlets" : 1, "numoutlets" : 0, "patching_rect" : [ 40.0, 12.0, 470.0, 20.0 ] } }
		],
		"lines" : [
			{ "patchline" : { "source" : [ "obj-grp", 0 ], "destination" : [ "obj-pg", 0 ] } },
			{ "patchline" : { "source" : [ "obj-pg", 0 ], "destination" : [ "obj-js", 0 ] } },
			{ "patchline" : { "source" : [ "obj-pat", 0 ], "destination" : [ "obj-pp", 0 ] } },
			{ "patchline" : { "source" : [ "obj-pp", 0 ], "destination" : [ "obj-js", 0 ] } },
			{ "patchline" : { "source" : [ "obj-trip", 0 ], "destination" : [ "obj-pt", 0 ] } },
			{ "patchline" : { "source" : [ "obj-pt", 0 ], "destination" : [ "obj-js", 0 ] } },
			{ "patchline" : { "source" : [ "obj-sc", 0 ], "destination" : [ "obj-psc", 0 ] } },
			{ "patchline" : { "source" : [ "obj-psc", 0 ], "destination" : [ "obj-js", 0 ] } },
			{ "patchline" : { "source" : [ "obj-oct", 0 ], "destination" : [ "obj-poc", 0 ] } },
			{ "patchline" : { "source" : [ "obj-poc", 0 ], "destination" : [ "obj-js", 0 ] } },
			{ "patchline" : { "source" : [ "obj-mtx", 0 ], "destination" : [ "obj-pc", 0 ] } },
			{ "patchline" : { "source" : [ "obj-pc", 0 ], "destination" : [ "obj-js", 0 ] } },
			{ "patchline" : { "source" : [ "obj-pitch", 0 ], "destination" : [ "obj-ppi", 0 ] } },
			{ "patchline" : { "source" : [ "obj-ppi", 0 ], "destination" : [ "obj-js", 0 ] } },
			{ "patchline" : { "source" : [ "obj-write", 0 ], "destination" : [ "obj-js", 0 ] } },
			{ "patchline" : { "source" : [ "obj-read", 0 ], "destination" : [ "obj-js", 0 ] } },
			{ "patchline" : { "source" : [ "obj-clear", 0 ], "destination" : [ "obj-js", 0 ] } },
			{ "patchline" : { "source" : [ "obj-dump", 0 ], "destination" : [ "obj-js", 0 ] } },

			{ "patchline" : { "source" : [ "obj-midiin", 0 ], "destination" : [ "obj-js", 1 ] } },
			{ "patchline" : { "source" : [ "obj-js", 0 ], "destination" : [ "obj-midiout", 0 ] } },
			{ "patchline" : { "source" : [ "obj-js", 1 ], "destination" : [ "obj-hex", 0 ] } },
			{ "patchline" : { "source" : [ "obj-js", 3 ], "destination" : [ "obj-stat", 0 ] } },

			{ "patchline" : { "source" : [ "obj-js", 2 ], "destination" : [ "obj-route", 0 ] } },
			{ "patchline" : { "source" : [ "obj-route", 0 ], "destination" : [ "obj-setg", 0 ] } },
			{ "patchline" : { "source" : [ "obj-setg", 0 ], "destination" : [ "obj-grp", 0 ] } },
			{ "patchline" : { "source" : [ "obj-route", 1 ], "destination" : [ "obj-setp", 0 ] } },
			{ "patchline" : { "source" : [ "obj-setp", 0 ], "destination" : [ "obj-pat", 0 ] } },
			{ "patchline" : { "source" : [ "obj-route", 2 ], "destination" : [ "obj-sett", 0 ] } },
			{ "patchline" : { "source" : [ "obj-sett", 0 ], "destination" : [ "obj-trip", 0 ] } },
			{ "patchline" : { "source" : [ "obj-route", 3 ], "destination" : [ "obj-sets", 0 ] } },
			{ "patchline" : { "source" : [ "obj-sets", 0 ], "destination" : [ "obj-sc", 0 ] } },
			{ "patchline" : { "source" : [ "obj-route", 4 ], "destination" : [ "obj-mtx", 0 ] } },
			{ "patchline" : { "source" : [ "obj-route", 5 ], "destination" : [ "obj-pitch", 0 ] } }
		]
	}
}
