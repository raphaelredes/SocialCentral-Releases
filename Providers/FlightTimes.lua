local _, ns = ...
local L = ns.L
local Compat = ns.Compat
local Safe = ns.Safe

-- WoW Forever (16001) Flight Map duration provider:
-- * Pre-populated with measured Classic Era continuous routes + Forever 1.60.1.70938
--   direct 3D spline durations (Eastern Kingdoms, Kalimdor, Riverglades, Mount Hyjal).
-- * Automatically sums intermediate hops, runs shortest-path fallback, supports
--   Forever's +20% Frequent Flier Legacy perk, and records real flown durations locally.
-- * Zero-taint hooksecurefunc / HookScript integration with weak-table tracking (0ms idle CPU).

local FlightTimes = {}
ns.FlightTimes = FlightTimes
table.insert(ns.modules, FlightTimes)

local FREQUENT_FLIER_NODE_ID = 110300
local FLIGHT_POLL_INTERVAL = 0.25
local TAKEOFF_TIMEOUT_SEC = 12

-- Base durations (seconds, without +20% Frequent Flier perk) keyed by [srcNodeID][dstNodeID].
local BASE_FLIGHT_TIMES = {
    [2] = { [4]=78, [5]=113, [6]=259, [7]=343, [8]=317, [12]=116, [14]=443, [16]=450, [19]=245, [43]=508, [45]=176, [66]=506, [67]=563, [71]=157, [74]=247 }, -- Stormwind, Elwynn
    [4] = { [2]=81, [5]=130, [6]=331, [7]=414, [8]=389, [12]=97, [19]=185, [45]=186, [74]=282 }, -- Sentinel Hill, Westfall
    [5] = { [2]=113, [4]=133, [6]=357, [7]=441, [8]=415, [12]=60, [14]=422, [19]=227, [67]=540, [71]=61, [74]=153, [3276]=132 }, -- Lakeshire, Redridge
    [6] = { [2]=210, [4]=274, [5]=201, [7]=128, [8]=101, [12]=260, [14]=265, [16]=253, [19]=440, [43]=298, [45]=373, [59]=278, [66]=294, [67]=349, [71]=173, [74]=87 }, -- Ironforge, Dun Morogh
    [7] = { [2]=261, [4]=324, [5]=250, [6]=89, [8]=163, [12]=309, [14]=107, [16]=113, [19]=490, [43]=176, [45]=423, [66]=186, [67]=324, [71]=221, [74]=135 }, -- Menethil Harbor, Wetlands
    [8] = { [2]=279, [4]=342, [5]=267, [6]=109, [7]=153, [12]=326, [14]=250, [16]=164, [19]=508, [45]=441, [66]=285, [71]=239, [74]=152, [3276]=184 }, -- Thelsamar, Loch Modan
    [10] = { [11]=112, [13]=95, [17]=212, [18]=863, [20]=782, [21]=471, [56]=751, [68]=299, [70]=556, [75]=526, [76]=289 }, -- The Sepulcher, Silverpine Forest
    [11] = { [10]=106, [13]=141, [17]=301, [18]=880, [20]=800, [21]=495, [56]=768, [60]=16, [68]=261, [70]=573, [75]=543, [76]=284 }, -- Undercity, Tirisfal
    [12] = { [2]=88, [4]=93, [5]=60, [6]=333, [7]=417, [8]=391, [14]=517, [16]=524, [19]=171, [43]=582, [45]=97, [74]=212 }, -- Darkshire, Duskwood
    [13] = { [10]=99, [11]=139, [17]=118, [18]=768, [20]=688, [21]=376, [56]=656, [68]=329, [70]=462, [75]=431, [76]=195 }, -- Tarren Mill, Hillsbrad
    [14] = { [2]=367, [4]=430, [6]=206, [7]=110, [8]=244, [12]=468, [16]=74, [19]=597, [43]=71, [66]=81, [67]=219, [74]=243 }, -- Southshore, Hillsbrad
    [16] = { [2]=385, [6]=271, [7]=126, [8]=171, [12]=485, [14]=86, [19]=614, [43]=72, [45]=547, [66]=122, [67]=233 }, -- Refuge Pointe, Arathi
    [17] = { [10]=215, [11]=259, [13]=117, [18]=651, [20]=571, [21]=259, [56]=539, [68]=229, [70]=344, [75]=314, [76]=91, [3203]=326 }, -- Hammerfall, Arathi
    [18] = { [10]=882, [11]=903, [13]=783, [17]=668, [20]=102, [21]=406, [56]=267, [68]=896, [70]=464, [75]=462, [76]=757 }, -- Booty Bay, Stranglethorn
    [19] = { [2]=220, [4]=181, [5]=230, [6]=464, [7]=548, [8]=523, [12]=175, [14]=649, [16]=655, [43]=714, [45]=266, [66]=712, [71]=291 }, -- Booty Bay, Stranglethorn
    [20] = { [10]=802, [11]=823, [13]=704, [17]=588, [18]=81, [21]=327, [56]=205, [68]=816, [70]=402, [75]=382, [76]=677 }, -- Grom'gol, Stranglethorn
    [21] = { [10]=477, [11]=497, [13]=379, [17]=263, [18]=417, [20]=313, [56]=280, [68]=491, [70]=87, [75]=56, [76]=352, [3203]=127 }, -- Kargath, Badlands
    [22] = { [23]=207, [25]=159, [29]=182, [30]=204, [38]=159, [40]=290, [42]=252, [44]=269, [48]=411, [53]=398, [55]=239, [58]=389, [61]=296, [69]=532, [72]=381, [77]=87, [79]=397, [80]=210 }, -- Thunder Bluff, Mulgore
    [23] = { [22]=224, [25]=110, [29]=260, [30]=294, [38]=385, [40]=417, [42]=361, [44]=99, [48]=252, [53]=319, [55]=229, [58]=250, [61]=89, [69]=361, [72]=492, [77]=200, [79]=494, [80]=161 }, -- Orgrimmar, Durotar
    [25] = { [22]=182, [23]=142, [29]=150, [30]=184, [38]=292, [40]=303, [42]=252, [44]=168, [48]=253, [53]=297, [55]=162, [58]=231, [61]=162, [72]=382, [77]=90, [79]=384, [80]=52 }, -- Crossroads, The Barrens
    [26] = { [27]=84, [28]=176, [32]=675, [33]=181, [37]=291, [39]=689, [41]=473, [49]=151, [52]=281, [64]=301, [65]=190, [80]=435 }, -- Auberdine, Darkshore
    [27] = { [26]=86, [28]=261, [31]=711, [32]=617, [33]=267, [37]=376, [39]=774, [41]=557, [49]=236, [52]=365, [64]=385, [65]=274, [73]=714, [79]=797, [80]=519 }, -- Rut'theran Village, Teldrassil
    [28] = { [26]=148, [27]=231, [32]=381, [33]=153, [37]=279, [39]=538, [41]=511, [64]=150, [65]=337, [80]=283 }, -- Astranaar, Ashenvale
    [29] = { [22]=175, [23]=290, [25]=150, [30]=333, [38]=143, [40]=426, [42]=339, [44]=318, [48]=403, [53]=447, [55]=312, [58]=380, [61]=311, [72]=469, [77]=240, [80]=200 }, -- Sun Rock Retreat, Stonetalon Mountains
    [30] = { [22]=225, [23]=335, [25]=194, [29]=343, [38]=323, [40]=93, [42]=124, [44]=362, [55]=315, [58]=424, [61]=356, [72]=252, [77]=137, [79]=200, [80]=245 }, -- Freewind Post, Thousand Needles
    [31] = { [27]=729, [32]=159, [37]=405, [39]=171, [41]=179, [79]=274, [80]=274 }, -- Thalanaar, Feralas
    [32] = { [26]=620, [27]=619, [28]=387, [31]=162, [33]=801, [37]=334, [39]=157, [41]=341, [49]=535, [52]=414, [64]=235, [65]=518, [73]=354, [79]=261, [80]=115 }, -- Theramore, Dustwallow Marsh
    [33] = { [26]=177, [27]=261, [28]=154, [32]=434, [37]=126, [41]=360 }, -- Stonetalon Peak, Stonetalon Mountains
    [37] = { [26]=282, [27]=367, [28]=273, [31]=472, [32]=308, [33]=120, [39]=464, [41]=232, [80]=422 }, -- Nijel's Point, Desolace
    [38] = { [22]=178, [23]=385, [25]=337, [29]=199, [30]=382, [40]=395, [42]=196, [44]=447, [48]=590, [53]=576, [55]=416, [58]=566, [61]=474, [69]=709, [72]=326, [77]=265, [79]=417, [80]=388 }, -- Shadowprey Village, Desolace
    [39] = { [27]=772, [28]=540, [31]=177, [32]=154, [33]=692, [37]=480, [41]=354, [52]=566, [64]=388, [65]=670, [73]=197, [79]=104, [80]=262 }, -- Gadgetzan, Tanaris
    [40] = { [22]=304, [23]=350, [25]=301, [29]=429, [30]=87, [38]=400, [42]=200, [44]=448, [48]=532, [53]=577, [55]=222, [58]=510, [61]=439, [69]=653, [72]=233, [77]=223, [79]=108, [80]=331 }, -- Gadgetzan, Tanaris
    [41] = { [26]=468, [27]=551, [28]=500, [31]=155, [32]=314, [33]=648, [37]=227, [39]=326, [49]=619, [52]=748, [64]=548, [73]=159 }, -- Feathermoon, Feralas
    [42] = { [22]=259, [23]=406, [25]=263, [29]=400, [30]=107, [38]=201, [40]=201, [44]=432, [48]=517, [55]=421, [58]=494, [61]=426, [72]=130, [77]=244, [79]=222, [80]=315 }, -- Camp Mojache, Feralas
    [43] = { [2]=429, [4]=492, [6]=256, [7]=176, [8]=245, [12]=531, [14]=68, [16]=75, [19]=658, [45]=591, [66]=54, [67]=164 }, -- Aerie Peak, The Hinterlands
    [44] = { [22]=257, [23]=121, [25]=172, [29]=322, [30]=357, [38]=416, [42]=423, [48]=232, [53]=131, [55]=335, [58]=253, [61]=94, [69]=264, [72]=553, [77]=263, [79]=556, [80]=223 }, -- Valormok, Azshara
    [45] = { [2]=189, [5]=150, [6]=382, [7]=467, [8]=483, [12]=91, [19]=260, [66]=631, [67]=687, [71]=207, [74]=300 }, -- Nethergarde Keep, Blasted Lands
    [48] = { [22]=423, [23]=259, [25]=241, [29]=390, [38]=533, [40]=518, [42]=493, [44]=241, [53]=190, [55]=404, [58]=471, [61]=333, [69]=166, [72]=623, [77]=331, [79]=625, [80]=292 }, -- Bloodvenom Post, Felwood
    [49] = { [26]=142, [27]=226, [28]=318, [32]=537, [37]=433, [39]=694, [41]=614, [52]=131, [64]=305, [65]=61, [73]=771 }, -- Moonglade
    [52] = { [26]=262, [27]=346, [28]=327, [31]=572, [32]=408, [33]=444, [37]=553, [39]=564, [41]=734, [49]=122, [64]=176, [65]=122, [80]=309, [3242]=135 }, -- Everlook, Winterspring
    [53] = { [22]=392, [23]=304, [25]=307, [29]=456, [38]=550, [40]=584, [42]=558, [44]=135, [48]=195, [55]=470, [58]=388, [61]=228, [69]=134, [72]=688, [77]=397, [79]=691, [80]=357, [3242]=136 }, -- Everlook, Winterspring
    [55] = { [22]=224, [23]=217, [25]=162, [29]=311, [30]=309, [38]=383, [40]=222, [42]=414, [44]=316, [48]=415, [53]=445, [61]=306, [72]=430, [77]=252, [79]=329, [80]=214 }, -- Brackenwall Village, Dustwallow Marsh
    [56] = { [10]=761, [11]=782, [13]=663, [17]=547, [18]=260, [20]=189, [21]=285, [68]=774, [70]=197, [75]=267, [76]=636, [3203]=170 }, -- Stonard, Swamp of Sorrows
    [58] = { [22]=410, [23]=256, [25]=228, [29]=378, [30]=412, [40]=504, [44]=256, [48]=481, [53]=384, [55]=391, [61]=167, [77]=318, [79]=611, [80]=279 }, -- Zoram'gar Outpost, Ashenvale
    [59] = { [6]=278 }, -- Dun Baldar, Alterac Valley
    [60] = { [11]=16 }, -- Frostwolf Keep, Alterac Valley
    [61] = { [22]=321, [23]=96, [25]=160, [29]=310, [30]=345, [38]=453, [40]=436, [42]=412, [44]=96, [48]=327, [53]=224, [55]=323, [58]=166, [69]=356, [72]=541, [77]=250, [79]=544, [80]=212 }, -- Splintertree Post, Ashenvale
    [62] = { [27]=152 }, -- Nighthaven, Moonglade
    [63] = { [22]=544 }, -- Nighthaven, Moonglade
    [64] = { [26]=301, [28]=153, [32]=241, [39]=391, [52]=178, [65]=283, [73]=588, [79]=494, [80]=135 }, -- Talrendis Point, Azshara
    [65] = { [26]=188, [27]=272, [28]=363, [33]=370, [37]=478, [39]=671, [41]=660, [49]=68, [52]=121, [64]=282, [79]=776 }, -- Talonbranch Glade, Felwood
    [66] = { [2]=432, [4]=495, [6]=261, [7]=193, [12]=535, [14]=85, [16]=138, [19]=662, [43]=66, [67]=147, [71]=395, [74]=309 }, -- Chillwind Camp, Western Plaguelands
    [67] = { [2]=542, [6]=369, [7]=333, [12]=591, [14]=226, [43]=163, [45]=704, [66]=150, [71]=503, [74]=417 }, -- Light's Hope Chapel, Eastern Plaguelands
    [68] = { [10]=294, [11]=262, [13]=301, [17]=234, [18]=884, [20]=804, [21]=492, [56]=773, [70]=578, [75]=547, [76]=141 }, -- Light's Hope Chapel, Eastern Plaguelands
    [69] = { [22]=532, [23]=370, [25]=353, [29]=502, [30]=537, [38]=645, [40]=629, [42]=604, [44]=275, [48]=157, [53]=142, [55]=515, [58]=528, [61]=369, [72]=734, [77]=443, [79]=736, [80]=404 }, -- Moonglade
    [70] = { [10]=576, [11]=597, [13]=477, [17]=361, [18]=472, [20]=401, [21]=99, [56]=213, [68]=589, [75]=72, [76]=451, [3203]=137 }, -- Flame Crest, Burning Steppes
    [71] = { [2]=151, [4]=195, [5]=64, [6]=187, [7]=270, [8]=245, [12]=121, [16]=378, [19]=288, [43]=436, [45]=210, [66]=435, [67]=491, [74]=104, [3276]=131 }, -- Morgan's Vigil, Burning Steppes
    [72] = { [22]=389, [23]=535, [25]=394, [30]=236, [38]=330, [40]=241, [42]=129, [44]=562, [55]=425, [69]=768, [77]=373, [79]=97, [80]=445 }, -- Cenarion Hold, Silithus
    [73] = { [27]=726, [31]=329, [32]=342, [39]=188, [41]=175, [64]=576, [65]=831, [79]=92 }, -- Cenarion Hold, Silithus
    [74] = { [6]=94, [7]=178, [8]=152, [14]=280, [45]=265, [66]=342, [67]=398, [71]=96 }, -- Thorium Point, Searing Gorge
    [75] = { [10]=545, [11]=566, [13]=447, [17]=331, [18]=462, [20]=382, [21]=70, [56]=350, [68]=559, [70]=77, [76]=420 }, -- Thorium Point, Searing Gorge
    [76] = { [10]=257, [11]=284, [13]=159, [17]=93, [18]=743, [20]=663, [21]=351, [56]=631, [68]=139, [70]=437, [75]=407 }, -- Revantusk Village, The Hinterlands
    [77] = { [22]=114, [23]=221, [25]=79, [29]=229, [30]=125, [38]=273, [40]=218, [42]=248, [55]=242, [61]=242, [72]=378, [79]=325, [80]=130 }, -- Camp Taurajo, The Barrens
    [79] = { [22]=416, [23]=462, [25]=392, [27]=809, [28]=856, [29]=542, [30]=200, [32]=257, [38]=424, [39]=104, [40]=113, [41]=258, [42]=224, [44]=559, [48]=645, [52]=670, [53]=689, [55]=333, [61]=551, [65]=774, [69]=766, [72]=100, [73]=94, [77]=336 }, -- Marshal's Refuge, Un'Goro Crater
    [80] = { [22]=250, [23]=210, [25]=69, [27]=805, [28]=284, [29]=218, [30]=252, [31]=268, [32]=106, [33]=437, [37]=439, [38]=360, [39]=261, [40]=345, [41]=446, [42]=320, [44]=236, [52]=310, [53]=366, [55]=231, [58]=299, [61]=231, [64]=132, [65]=415, [72]=450, [73]=459, [77]=158 }, -- Ratchet, The Barrens
    [84] = { [85]=49, [86]=63, [87]=51 }, -- Plaguewood Tower, Eastern Plaguelands
    [559] = { [3242]=62 }, -- Summit of Eternity, Mount Hyjal
    [3203] = { [17]=328, [21]=120, [56]=154, [70]=133 }, -- Rog'mar, Riverglades
    [3242] = { [52]=125, [53]=132, [559]=62 }, -- Tainted Foothills, Mount Hyjal
    [3276] = { [5]=131, [8]=173, [71]=123 }, -- Farholde Keep, Riverglades
}

-- Direct single-hop graph edges for WoW Forever 16001 (used for shortest-path fallback).
local DIRECT_EDGES = {
    [2] = { [4]=78, [5]=113, [6]=259, [12]=116, [19]=244, [45]=176, [71]=157 },
    [4] = { [2]=81, [5]=130, [12]=97, [19]=185 },
    [5] = { [2]=112, [4]=133, [12]=60, [71]=61, [3276]=132 },
    [6] = { [2]=210, [7]=129, [8]=101, [14]=265, [16]=253, [43]=298, [59]=278, [66]=294, [67]=348, [74]=86 },
    [7] = { [6]=89, [8]=163, [14]=107, [16]=113 },
    [8] = { [6]=109, [7]=152, [16]=163, [3276]=184 },
    [10] = { [11]=111, [13]=96 },
    [11] = { [10]=106, [13]=141, [17]=300, [21]=495, [60]=16, [68]=262, [76]=284 },
    [12] = { [2]=88, [4]=93, [5]=60, [19]=171, [45]=97 },
    [13] = { [10]=100, [11]=139, [17]=118, [76]=195 },
    [14] = { [6]=206, [7]=110, [16]=74, [43]=71, [66]=81 },
    [16] = { [6]=270, [7]=126, [8]=170, [14]=87, [43]=72 },
    [17] = { [11]=259, [13]=116, [21]=259, [76]=90, [3203]=326 },
    [18] = { [20]=102, [21]=406, [56]=266 },
    [19] = { [2]=219, [4]=181, [12]=175 },
    [20] = { [18]=81, [21]=327, [56]=205 },
    [21] = { [11]=497, [17]=263, [18]=416, [20]=313, [56]=281, [70]=86, [75]=56, [3203]=127 },
    [22] = { [23]=207, [25]=158, [29]=181, [30]=204, [38]=158, [40]=290, [42]=252, [44]=269, [55]=238, [77]=87 },
    [23] = { [22]=225, [25]=110, [40]=417, [44]=99, [48]=252, [53]=319, [55]=228, [61]=89 },
    [25] = { [22]=182, [23]=142, [29]=150, [30]=184, [40]=303, [42]=252, [44]=168, [48]=253, [55]=163, [58]=230, [61]=162, [77]=90, [80]=52 },
    [26] = { [27]=84, [28]=176, [32]=674, [33]=181, [37]=291, [41]=472, [49]=151, [64]=299, [65]=189 },
    [27] = { [26]=85 },
    [28] = { [26]=148, [33]=153, [64]=148 },
    [29] = { [22]=174, [25]=149, [38]=143 },
    [30] = { [22]=225, [25]=194, [40]=93, [42]=123, [77]=137 },
    [31] = { [32]=159, [39]=171, [41]=178 },
    [32] = { [26]=621, [31]=163, [37]=334, [39]=156, [64]=235, [80]=115 },
    [33] = { [26]=177, [28]=154, [37]=127 },
    [37] = { [26]=282, [32]=307, [33]=119, [41]=232 },
    [38] = { [22]=178, [29]=199, [42]=196 },
    [39] = { [31]=177, [32]=154, [73]=197, [79]=104 },
    [40] = { [22]=304, [23]=350, [25]=300, [30]=87, [42]=199, [55]=222, [72]=233, [79]=107 },
    [41] = { [26]=467, [31]=155, [37]=227, [73]=159 },
    [42] = { [22]=259, [25]=264, [30]=107, [38]=201, [40]=201, [72]=130 },
    [43] = { [6]=255, [14]=68, [16]=76, [66]=53, [67]=164 },
    [44] = { [22]=257, [23]=121, [25]=172, [48]=232, [53]=130, [61]=93 },
    [45] = { [2]=189, [12]=92, [71]=208 },
    [48] = { [23]=258, [25]=241, [44]=241, [53]=190, [69]=165 },
    [49] = { [26]=142, [52]=130, [65]=61 },
    [52] = { [49]=121, [64]=176, [65]=122, [3242]=135 },
    [53] = { [23]=304, [44]=136, [48]=195, [69]=134, [3242]=136 },
    [55] = { [22]=224, [23]=217, [25]=162, [40]=222 },
    [56] = { [18]=260, [20]=188, [21]=285, [70]=197, [3203]=170 },
    [58] = { [25]=228, [61]=167 },
    [59] = { [6]=278 },
    [60] = { [11]=16 },
    [61] = { [23]=96, [25]=160, [44]=96, [58]=166 },
    [62] = { [27]=152 },
    [63] = { [22]=544 },
    [64] = { [26]=301, [28]=153, [32]=241, [52]=178, [65]=283, [80]=135 },
    [65] = { [26]=187, [49]=67, [52]=120, [64]=282 },
    [66] = { [6]=259, [14]=85, [43]=65, [67]=146 },
    [67] = { [6]=367, [43]=162, [66]=149 },
    [68] = { [11]=261, [76]=141 },
    [69] = { [48]=157, [53]=142 },
    [70] = { [21]=100, [56]=213, [75]=72, [3203]=137 },
    [71] = { [2]=151, [5]=63, [45]=210, [74]=103, [3276]=131 },
    [72] = { [40]=241, [42]=130, [79]=97 },
    [73] = { [39]=188, [41]=175, [79]=91 },
    [74] = { [6]=93, [71]=96 },
    [75] = { [21]=70, [70]=77 },
    [76] = { [11]=285, [13]=159, [17]=93, [68]=139 },
    [77] = { [22]=114, [25]=79, [30]=125 },
    [79] = { [39]=103, [40]=113, [72]=100, [73]=94 },
    [80] = { [25]=68, [32]=105, [64]=132 },
    [84] = { [85]=49, [86]=63, [87]=51 },
    [559] = { [3242]=62 },
    [3203] = { [17]=328, [21]=120, [56]=154, [70]=133 },
    [3242] = { [52]=125, [53]=132, [559]=62 },
    [3276] = { [5]=131, [8]=173, [71]=123 },
}

-- Localized fallback node lookup (EN / PT / ES) when C_TaxiMap.GetAllTaxiNodes lacks a slot.
local NODE_BY_NAME = {
    ["acampamento taurajo"] = 77,
    ["acampamento taurajo, sertões"] = 77,
    ["acampamento ventogelante"] = 66,
    ["acampamento ventogelante, terras pestilentas ocidentais"] = 66,
    ["aerie peak"] = 43,
    ["aerie peak, the hinterlands"] = 43,
    ["aldea cazasombras"] = 38,
    ["aldea cazasombras, desolace"] = 38,
    ["aldea rut'theran"] = 27,
    ["aldea rut'theran, teldrassil"] = 27,
    ["aldeia mojache"] = 42,
    ["aldeia mojache, feralas"] = 42,
    ["aldeia muralha verde"] = 55,
    ["aldeia muralha verde, pântano vadeoso"] = 55,
    ["aldeia pescassombra"] = 38,
    ["aldeia pescassombra, desolação"] = 38,
    ["aldeia revatusco"] = 76,
    ["aldeia revatusco, terras agrestes"] = 76,
    ["aldeia vento livre"] = 30,
    ["aldeia vento livre, mil agulhas"] = 30,
    ["altaforja"] = 6,
    ["altaforja, dun morogh"] = 6,
    ["amparo de la noche"] = { A = 62, H = 63 },
    ["amparo de la noche, claro de la luna"] = { A = 62, H = 63 },
    ["angra do butim"] = { A = 19, H = 18 },
    ["angra do butim, selva do espinhaço"] = { A = 19, H = 18 },
    ["assentamento zoram'gar"] = 58,
    ["assentamento zoram'gar, vale gris"] = 58,
    ["astranaar"] = 28,
    ["astranaar, ashenvale"] = 28,
    ["astranaar, vale gris"] = 28,
    ["astranaar, vallefresno"] = 28,
    ["auberdine"] = 26,
    ["auberdine, costa negra"] = 26,
    ["auberdine, costa oscura"] = 26,
    ["auberdine, darkshore"] = 26,
    ["avanzada de zoram'gar"] = 58,
    ["avanzada de zoram'gar, vallefresno"] = 58,
    ["bahía del botín"] = { A = 19, H = 18 },
    ["bahía del botín, tuercespina"] = { A = 19, H = 18 },
    ["bastilha de ermoforte"] = 3276,
    ["bastilha de ermoforte, sendas do rio"] = 3276,
    ["bastilha de etergarde"] = 45,
    ["bastilha de etergarde, barreira do inferno"] = 45,
    ["bastilha lobo do gelo"] = 60,
    ["bastilha lobo do gelo, vale alterac"] = 60,
    ["bastión lobo gélido"] = 60,
    ["bastión lobo gélido, valle de alterac"] = 60,
    ["bloodvenom post"] = 48,
    ["bloodvenom post, felwood"] = 48,
    ["booty bay"] = { A = 19, H = 18 },
    ["booty bay, stranglethorn"] = { A = 19, H = 18 },
    ["brackenwall village"] = 55,
    ["brackenwall village, dustwallow marsh"] = 55,
    ["camp mojache"] = 42,
    ["camp mojache, feralas"] = 42,
    ["camp taurajo"] = 77,
    ["camp taurajo, the barrens"] = 77,
    ["campamento del orvallo"] = 66,
    ["campamento del orvallo, tierras de la peste del oeste"] = 66,
    ["campamento mojache"] = 42,
    ["campamento mojache, feralas"] = 42,
    ["campamento taurajo"] = 77,
    ["campamento taurajo, los baldíos"] = 77,
    ["campo talrendis"] = 64,
    ["campo talrendis, azshara"] = 64,
    ["capela esperança da luz"] = { A = 67, H = 68 },
    ["capela esperança da luz, terras pestilentas orientais"] = { A = 67, H = 68 },
    ["capilla de la esperanza de la luz"] = { A = 67, H = 68 },
    ["capilla de la esperanza de la luz, tierras de la peste del este"] = { A = 67, H = 68 },
    ["castillo de farholde"] = 3276,
    ["castillo de farholde, clarofluvial"] = 3276,
    ["castillo de nethergarde"] = 45,
    ["castillo de nethergarde, las tierras devastadas"] = 45,
    ["cenarion hold"] = { A = 73, H = 72 },
    ["cenarion hold, silithus"] = { A = 73, H = 72 },
    ["chillwind camp"] = 66,
    ["chillwind camp, western plaguelands"] = 66,
    ["cidade baixa"] = 11,
    ["cidade baixa, tirisfal"] = 11,
    ["cima de la eternidad"] = 559,
    ["cima de la eternidad, monte hyjal"] = 559,
    ["cima del espolón"] = 33,
    ["cima del espolón, sierra espolón"] = 33,
    ["cima del trueno"] = 22,
    ["cima del trueno, mulgore"] = 22,
    ["clareira da galhaça"] = 65,
    ["clareira da galhaça, selva maleva"] = 65,
    ["clareira da lua"] = { A = 49, H = 69 },
    ["claro de la luna"] = { A = 49, H = 69 },
    ["claro ramaespolón"] = 65,
    ["claro ramaespolón, frondavil"] = 65,
    ["colina del centinela"] = 4,
    ["colina del centinela, páramos de poniente"] = 4,
    ["contraforte maculado"] = 3242,
    ["contraforte maculado, monte hyjal"] = 3242,
    ["costa sul"] = 14,
    ["costa sul, eira dos montes"] = 14,
    ["costasur"] = 14,
    ["costasur, trabalomas"] = 14,
    ["crossroads"] = 25,
    ["crossroads, the barrens"] = 25,
    ["crown guard tower"] = 87,
    ["crown guard tower, eastern plaguelands"] = 87,
    ["darkshire"] = 12,
    ["darkshire, duskwood"] = 12,
    ["dun baldar"] = 59,
    ["dun baldar, alterac valley"] = 59,
    ["dun baldar, vale alterac"] = 59,
    ["dun baldar, valle de alterac"] = 59,
    ["eastwall tower"] = 86,
    ["eastwall tower, eastern plaguelands"] = 86,
    ["el cruce"] = 25,
    ["el cruce, los baldíos"] = 25,
    ["el sepulcro"] = 10,
    ["el sepulcro, bosque de argénteos"] = 10,
    ["encruzilhada"] = 25,
    ["encruzilhada, sertões"] = 25,
    ["entrañas"] = 11,
    ["entrañas, tirisfal"] = 11,
    ["everlook"] = { A = 52, H = 53 },
    ["everlook, winterspring"] = { A = 52, H = 53 },
    ["farholde keep"] = 3276,
    ["farholde keep, riverglades"] = 3276,
    ["feathermoon"] = 41,
    ["feathermoon, feralas"] = 41,
    ["flame crest"] = 70,
    ["flame crest, burning steppes"] = 70,
    ["forjaz"] = 6,
    ["forjaz, dun morogh"] = 6,
    ["fortaleza de farholde"] = 3276,
    ["fortaleza de farholde, claros del río"] = 3276,
    ["forte cenariano"] = { A = 73, H = 72 },
    ["forte cenariano, silithus"] = { A = 73, H = 72 },
    ["freewind post"] = 30,
    ["freewind post, thousand needles"] = 30,
    ["frostwolf keep"] = 60,
    ["frostwolf keep, alterac valley"] = 60,
    ["fuerte cenarion"] = { A = 73, H = 72 },
    ["fuerte cenarion, silithus"] = { A = 73, H = 72 },
    ["gadgetzan"] = { A = 39, H = 40 },
    ["gadgetzan, tanaris"] = { A = 39, H = 40 },
    ["geringontzan"] = { A = 39, H = 40 },
    ["geringontzan, tanaris"] = { A = 39, H = 40 },
    ["grom'gol"] = 20,
    ["grom'gol, selva do espinhaço"] = 20,
    ["grom'gol, stranglethorn"] = 20,
    ["grom'gol, tuercespina"] = 20,
    ["hammerfall"] = 17,
    ["hammerfall, arathi"] = 17,
    ["ironforge"] = 6,
    ["ironforge, dun morogh"] = 6,
    ["kargath"] = 21,
    ["kargath, badlands"] = 21,
    ["kargath, tierras inhóspitas"] = 21,
    ["karrath"] = 21,
    ["karrath, ermos"] = 21,
    ["laderas maculadas"] = 3242,
    ["laderas maculadas, monte hyjal"] = 3242,
    ["laderas máculas"] = 3242,
    ["laderas máculas, monte hyjal"] = 3242,
    ["lakeshire"] = 5,
    ["lakeshire, redridge"] = 5,
    ["light's hope chapel"] = { A = 67, H = 68 },
    ["light's hope chapel, eastern plaguelands"] = { A = 67, H = 68 },
    ["marshal's refuge"] = 79,
    ["marshal's refuge, un'goro crater"] = 79,
    ["menethil harbor"] = 7,
    ["menethil harbor, wetlands"] = 7,
    ["molino tarren"] = 13,
    ["molino tarren, trabalomas"] = 13,
    ["monte candente"] = 70,
    ["monte candente, estepes ardentes"] = 70,
    ["moonglade"] = { A = 49, H = 69 },
    ["morgan's vigil"] = 71,
    ["morgan's vigil, burning steppes"] = 71,
    ["morro da sentinela"] = 4,
    ["morro da sentinela, cerro oeste"] = 4,
    ["morro das torres de pedra"] = 33,
    ["morro das torres de pedra, cordilheira das torres de pedra"] = 33,
    ["nethergarde keep"] = 45,
    ["nethergarde keep, blasted lands"] = 45,
    ["nighthaven"] = { A = 62, H = 63 },
    ["nighthaven, moonglade"] = { A = 62, H = 63 },
    ["nijel's point"] = 37,
    ["nijel's point, desolace"] = 37,
    ["ninho da águia"] = 43,
    ["ninho da águia, terras agrestes"] = 43,
    ["northpass tower"] = 85,
    ["northpass tower, eastern plaguelands"] = 85,
    ["o sepulcro"] = 10,
    ["o sepulcro, floresta de pinhaprata"] = 10,
    ["orgrimmar"] = 23,
    ["orgrimmar, durotar"] = 23,
    ["pedregal"] = 56,
    ["pedregal, pântano das mágoas"] = 56,
    ["penhasco do trovão"] = 22,
    ["penhasco do trovão, mulgore"] = 22,
    ["peñasco llamarada"] = 70,
    ["peñasco llamarada, las estepas ardientes"] = 70,
    ["pico da eternidade"] = 559,
    ["pico da eternidade, monte hyjal"] = 559,
    ["pico nidal"] = 43,
    ["pico nidal, tierras del interior"] = 43,
    ["plaguewood tower"] = 84,
    ["plaguewood tower, eastern plaguelands"] = 84,
    ["plumaluna"] = 41,
    ["plumaluna, feralas"] = 41,
    ["poblado murohelecho"] = 55,
    ["poblado murohelecho, marjal revolcafango"] = 55,
    ["poblado sañadiente"] = 76,
    ["poblado sañadiente, tierras del interior"] = 76,
    ["poblado viento libre"] = 30,
    ["poblado viento libre, las mil agujas"] = 30,
    ["ponta do refúgio"] = 16,
    ["ponta do refúgio, arathi"] = 16,
    ["porto de menethil"] = 7,
    ["porto de menethil, pantanal"] = 7,
    ["posto de tório"] = { A = 74, H = 75 },
    ["posto de tório, garganta abrasadora"] = { A = 74, H = 75 },
    ["posto do nijel"] = 37,
    ["posto do nijel, desolação"] = 37,
    ["posto machadada"] = 61,
    ["posto machadada, vale gris"] = 61,
    ["posto peçonha"] = 48,
    ["posto peçonha, selva maleva"] = 48,
    ["puerto de menethil"] = 7,
    ["puerto de menethil, los humedales"] = 7,
    ["puesto del hachazo"] = 61,
    ["puesto del hachazo, vallefresno"] = 61,
    ["puesto del thorium"] = { A = 74, H = 75 },
    ["puesto del thorium, la garganta de fuego"] = { A = 74, H = 75 },
    ["puesto del torio"] = { A = 74, H = 75 },
    ["puesto del torio, la garganta de fuego"] = { A = 74, H = 75 },
    ["puesto del veneno"] = 48,
    ["puesto del veneno, frondavil"] = 48,
    ["punta de nijel"] = 37,
    ["punta de nijel, desolace"] = 37,
    ["punta talrendis"] = 64,
    ["punta talrendis, azshara"] = 64,
    ["ratchet"] = 80,
    ["ratchet, the barrens"] = 80,
    ["refuge pointe"] = 16,
    ["refuge pointe, arathi"] = 16,
    ["refugio de la zaga"] = 16,
    ["refugio de la zaga, arathi"] = 16,
    ["refugio de marshal"] = 79,
    ["refugio de marshal, cráter de un'goro"] = 79,
    ["refugio roca del sol"] = 29,
    ["refugio roca del sol, sierra espolón"] = 29,
    ["refúgio do marshal"] = 79,
    ["refúgio do marshal, cratera un'goro"] = 79,
    ["refúgio noturno"] = { A = 62, H = 63 },
    ["refúgio noturno, clareira da lua"] = { A = 62, H = 63 },
    ["retiro rocha do sol"] = 29,
    ["retiro rocha do sol, cordilheira das torres de pedra"] = 29,
    ["revantusk village"] = 76,
    ["revantusk village, the hinterlands"] = 76,
    ["rocal"] = 56,
    ["rocal, pantano de las penas"] = 56,
    ["rog'mar"] = 3203,
    ["rog'mar, clarofluvial"] = 3203,
    ["rog'mar, claros del río"] = 3203,
    ["rog'mar, riverglades"] = 3203,
    ["rog'mar, sendas do rio"] = 3203,
    ["rut'theran village"] = 27,
    ["rut'theran village, teldrassil"] = 27,
    ["ruína do martelo"] = 17,
    ["ruína do martelo, arathi"] = 17,
    ["sentencia"] = 17,
    ["sentencia, arathi"] = 17,
    ["sentinel hill"] = 4,
    ["sentinel hill, westfall"] = 4,
    ["serraria tarren"] = 13,
    ["serraria tarren, eira dos montes"] = 13,
    ["shadowprey village"] = 38,
    ["shadowprey village, desolace"] = 38,
    ["southshore"] = 14,
    ["southshore, hillsbrad"] = 14,
    ["splintertree post"] = 61,
    ["splintertree post, ashenvale"] = 61,
    ["stonard"] = 56,
    ["stonard, swamp of sorrows"] = 56,
    ["stonetalon peak"] = 33,
    ["stonetalon peak, stonetalon mountains"] = 33,
    ["stormwind"] = 2,
    ["stormwind, elwynn"] = 2,
    ["summit of eternity"] = 559,
    ["summit of eternity, mount hyjal"] = 559,
    ["sun rock retreat"] = 29,
    ["sun rock retreat, stonetalon mountains"] = 29,
    ["tainted foothills"] = 3242,
    ["tainted foothills, mount hyjal"] = 3242,
    ["talonbranch glade"] = 65,
    ["talonbranch glade, felwood"] = 65,
    ["talrendis point"] = 64,
    ["talrendis point, azshara"] = 64,
    ["tarren mill"] = 13,
    ["tarren mill, hillsbrad"] = 13,
    ["thalanaar"] = 31,
    ["thalanaar, feralas"] = 31,
    ["the sepulcher"] = 10,
    ["the sepulcher, silverpine forest"] = 10,
    ["thelsamar"] = 8,
    ["thelsamar, loch modan"] = 8,
    ["theramore"] = 32,
    ["theramore, dustwallow marsh"] = 32,
    ["theramore, marjal revolcafango"] = 32,
    ["theramore, pântano vadeoso"] = 32,
    ["thorium point"] = { A = 74, H = 75 },
    ["thorium point, searing gorge"] = { A = 74, H = 75 },
    ["thunder bluff"] = 22,
    ["thunder bluff, mulgore"] = 22,
    ["torre da coroa"] = 87,
    ["torre da coroa, terras pestilentas orientais"] = 87,
    ["torre da muralha leste"] = 86,
    ["torre da muralha leste, terras pestilentas orientais"] = 86,
    ["torre de la corona"] = 87,
    ["torre de la corona, tierras de la peste del este"] = 87,
    ["torre de la muralla del este"] = 86,
    ["torre de la muralla del este, tierras de la peste del este"] = 86,
    ["torre del bosque de la peste"] = 84,
    ["torre del bosque de la peste, tierras de la peste de este"] = 84,
    ["torre del paso norte"] = 85,
    ["torre del paso norte, tierras de la peste del este"] = 85,
    ["torre do bosque pestilento"] = 84,
    ["torre do bosque pestilento, terras pestilentas orientais"] = 84,
    ["torre do passo norte"] = 85,
    ["torre do passo norte, terras pestilentas orientais"] = 85,
    ["trinquete"] = 80,
    ["trinquete, los baldíos"] = 80,
    ["undercity"] = 11,
    ["undercity, tirisfal"] = 11,
    ["valormok"] = 44,
    ["valormok, azshara"] = 44,
    ["ventobravo"] = 2,
    ["ventobravo, elwynn"] = 2,
    ["ventormenta"] = 2,
    ["ventormenta, elwynn"] = 2,
    ["vigia de morgan"] = 71,
    ["vigia de morgan, estepes ardentes"] = 71,
    ["vigilia de morgan"] = 71,
    ["vigilia de morgan, las estepas ardientes"] = 71,
    ["vila catraca"] = 80,
    ["vila catraca, sertões"] = 80,
    ["vila de rut'theran"] = 27,
    ["vila de rut'theran, teldrassil"] = 27,
    ["vila plácida"] = 5,
    ["vila plácida, montanhas cristarrubra"] = 5,
    ["vila sombria"] = 12,
    ["vila sombria, floresta do crepúsculo"] = 12,
    ["villa del lago"] = 5,
    ["villa del lago, crestagrana"] = 5,
    ["villa oscura"] = 12,
    ["villa oscura, bosque del ocaso"] = 12,
    ["vista eterna"] = { A = 52, H = 53 },
    ["vista eterna, cuna del invierno"] = { A = 52, H = 53 },
    ["visteterna"] = { A = 52, H = 53 },
    ["visteterna, hibérnia"] = { A = 52, H = 53 },
    ["zoram'gar outpost"] = 58,
    ["zoram'gar outpost, ashenvale"] = 58,
}

local hookedWidgets = setmetatable({}, { __mode = "k" })
local globalHooksInstalled = false
local loadUiHookInstalled = false

local currentNodeID = nil
local currentSlot = nil
local slotToNodeID = {}
local bindSeq = 0

local flightTicker = nil
local pendingSrcID = nil
local pendingDstID = nil
local pendingSince = nil
local flightStartAt = nil
local confirmedOnTaxi = false
local pendingSrcName = nil
local pendingDstName = nil
local pendingEstSec = nil
local pendingQuality = nil
local pendingCanSave = false

local timerBar = nil
local activeFlightInfo = nil
local demoFlightActive = false
local demoFlightStartAt = 0
local demoFlightEstSec = 285
local barDismissedForFlight = false

local TIMER_BAR_W = 336
local TIMER_BAR_H = 46
local ICON_FLIGHT_GRYPHON = "Interface\\Icons\\Ability_Mount_Gryphon_01"
local WHITE8X8_TEX = "Interface\\Buttons\\WHITE8X8"

local function IsFeatureEnabled()
    local s = ns.db and ns.db.settings
    if s and s.flightMapTimesEnabled == false then
        return false
    end
    return true
end

local function IsTimerBarEnabled()
    local s = ns.db and ns.db.settings
    if s and s.flightTimerBarEnabled == false then
        return false
    end
    return true
end

local function GetSavedTimesTable()
    if not ns.db then
        return nil
    end
    if type(ns.db.flightTimes) ~= "table" then
        ns.db.flightTimes = {}
    end
    return ns.db.flightTimes
end

local function NormalizeNodeName(rawName)
    local s = (Safe and Safe.String) and Safe.String(rawName) or (type(rawName) == "string" and rawName or nil)
    if not s or s == "" then
        return nil, nil
    end
    local trimmed = s:match("^%s*(.-)%s*$") or s
    local low = (Compat and Compat.LowerUtf8) and Compat.LowerUtf8(trimmed) or trimmed:lower()
    local short = low:match("^([^,]+)")
    if short then
        short = short:match("^%s*(.-)%s*$") or short
    end
    return low, short
end

local function HasFrequentFlierPerk()
    local legacy = _G.Constants and _G.Constants.LegacyConsts
    local treeID = legacy and legacy.LEGACY_TREE_ADVENTURE_ID
    if not (treeID and _G.C_Traits and _G.C_Traits.GetConfigIDByTreeID and _G.C_Traits.GetNodeInfo) then
        return false
    end
    local okCfg, configID = pcall(_G.C_Traits.GetConfigIDByTreeID, treeID)
    if not (okCfg and configID) then
        return false
    end
    local okNode, info = pcall(_G.C_Traits.GetNodeInfo, configID, FREQUENT_FLIER_NODE_ID)
    if not (okNode and type(info) == "table") then
        return false
    end
    local rank = (Safe and Safe.Number) and Safe.Number(info.activeRank) or nil
    return (rank ~= nil and rank > 0)
end

local function BaseToDisplaySeconds(baseSeconds)
    if type(baseSeconds) ~= "number" or baseSeconds <= 0 then
        return nil
    end
    if HasFrequentFlierPerk() then
        return math.max(1, math.floor((baseSeconds / 1.2) + 0.5))
    end
    return math.max(1, math.floor(baseSeconds + 0.5))
end

local function ActualToBaseSeconds(actualSeconds)
    if type(actualSeconds) ~= "number" or actualSeconds <= 0 then
        return nil
    end
    if HasFrequentFlierPerk() then
        return math.max(1, math.floor((actualSeconds * 1.2) + 0.5))
    end
    return math.max(1, math.floor(actualSeconds + 0.5))
end

local function FormatDuration(seconds)
    if type(seconds) ~= "number" or seconds <= 0 then
        return nil
    end
    local total = math.max(1, math.floor(seconds + 0.5))
    local mins = math.floor(total / 60)
    local secs = total % 60
    if mins > 0 then
        return string.format("%dm %02ds", mins, secs)
    end
    return string.format("%ds", secs)
end

local function GetViewedTaxiMapID()
    if _G.FlightMapFrame and _G.FlightMapFrame.GetMapID then
        local okF, mID = pcall(_G.FlightMapFrame.GetMapID, _G.FlightMapFrame)
        local cleanID = okF and ((Safe and Safe.Number) and Safe.Number(mID) or nil) or nil
        if cleanID and cleanID > 0 then
            return cleanID
        end
    end
    if _G.GetTaxiMapID then
        local okT, mID = pcall(_G.GetTaxiMapID)
        local cleanID = okT and ((Safe and Safe.Number) and Safe.Number(mID) or nil) or nil
        if cleanID and cleanID > 0 then
            return cleanID
        end
    end
    return nil
end

local function LookupNodeIDByName(rawName)
    local fullLow, shortLow = NormalizeNodeName(rawName)
    if not fullLow then
        return nil
    end
    local entry = NODE_BY_NAME[fullLow] or (shortLow and NODE_BY_NAME[shortLow]) or nil
    if type(entry) == "number" then
        return entry
    end
    if type(entry) == "table" then
        local faction = nil
        if _G.UnitFactionGroup then
            local okF, fac = pcall(_G.UnitFactionGroup, "player")
            if okF then
                faction = (Safe and Safe.String) and Safe.String(fac) or (type(fac) == "string" and fac or nil)
            end
        end
        if faction == "Horde" then
            return entry.H or entry.A
        end
        return entry.A or entry.H
    end
    return nil
end

local function RefreshTaxiSlotCache()
    wipe(slotToNodeID)
    currentNodeID = nil
    currentSlot = nil

    if _G.C_TaxiMap and _G.C_TaxiMap.GetAllTaxiNodes then
        local mapID = GetViewedTaxiMapID()
        if mapID then
            local okNodes, nodes = pcall(_G.C_TaxiMap.GetAllTaxiNodes, mapID)
            if okNodes and type(nodes) == "table" then
                local curState = _G.Enum and _G.Enum.FlightPathState and _G.Enum.FlightPathState.Current
                for i = 1, #nodes do
                    local node = nodes[i]
                    if type(node) == "table" then
                        local nid = (Safe and Safe.Number) and Safe.Number(node.nodeID) or nil
                        local sIdx = (Safe and Safe.Number) and Safe.Number(node.slotIndex) or nil
                        if nid and sIdx then
                            slotToNodeID[sIdx] = nid
                        end
                        if nid and curState ~= nil and node.state == curState then
                            currentNodeID = nid
                            currentSlot = sIdx
                        end
                    end
                end
            end
        end
    end

    if _G.NumTaxiNodes and _G.TaxiNodeGetType then
        local okCnt, cnt = pcall(_G.NumTaxiNodes)
        local n = okCnt and ((Safe and Safe.Number) and Safe.Number(cnt) or nil) or 0
        for slot = 1, n do
            if not slotToNodeID[slot] and _G.TaxiNodeName then
                local okNm, nm = pcall(_G.TaxiNodeName, slot)
                if okNm and nm then
                    local guessed = LookupNodeIDByName(nm)
                    if guessed then
                        slotToNodeID[slot] = guessed
                    end
                end
            end
            local okTp, tp = pcall(_G.TaxiNodeGetType, slot)
            if okTp and tp == "CURRENT" then
                currentSlot = slot
                if slotToNodeID[slot] then
                    currentNodeID = slotToNodeID[slot]
                end
            end
        end
    end
end

local function ResolveNodeID(slot)
    if not slot then
        return nil
    end
    if slotToNodeID[slot] then
        return slotToNodeID[slot]
    end
    RefreshTaxiSlotCache()
    if slotToNodeID[slot] then
        return slotToNodeID[slot]
    end
    if _G.TaxiNodeName then
        local okNm, nm = pcall(_G.TaxiNodeName, slot)
        if okNm and nm then
            local byName = LookupNodeIDByName(nm)
            if byName then
                slotToNodeID[slot] = byName
                return byName
            end
        end
    end
    return nil
end

local function IsReachableState(nodeType)
    if nodeType == "REACHABLE" then
        return true
    end
    local enumReach = _G.Enum and _G.Enum.FlightPathState and _G.Enum.FlightPathState.Reachable
    if enumReach ~= nil and nodeType == enumReach then
        return true
    end
    return false
end

local function LookupDirectLegSeconds(fromID, toID)
    if not (fromID and toID) then
        return nil
    end
    local saved = GetSavedTimesTable()
    local custom = saved and saved[fromID] and saved[fromID][toID]
    if type(custom) == "number" and custom > 0 then
        return custom
    end
    local direct = DIRECT_EDGES[fromID] and DIRECT_EDGES[fromID][toID]
    if type(direct) == "number" and direct > 0 then
        return direct
    end
    local base = BASE_FLIGHT_TIMES[fromID] and BASE_FLIGHT_TIMES[fromID][toID]
    if type(base) == "number" and base > 0 then
        return base
    end
    return nil
end

local function FindShortestGraphDuration(srcID, dstID)
    if not (srcID and dstID and DIRECT_EDGES[srcID]) then
        return nil
    end
    local dist = { [srcID] = 0 }
    local visited = {}
    for _ = 1, 80 do
        local bestNode = nil
        local bestDist = nil
        for nid, d in pairs(dist) do
            if not visited[nid] and (bestDist == nil or d < bestDist) then
                bestNode = nid
                bestDist = d
            end
        end
        if not bestNode then
            break
        end
        if bestNode == dstID then
            return bestDist
        end
        visited[bestNode] = true
        local edges = DIRECT_EDGES[bestNode]
        if edges then
            for nxt, sec in pairs(edges) do
                if not visited[nxt] and type(sec) == "number" and sec > 0 then
                    local cand = bestDist + sec
                    if dist[nxt] == nil or cand < dist[nxt] then
                        dist[nxt] = cand
                    end
                end
            end
        end
    end
    return nil
end

local function EstimateByMapDistance(srcSlot, dstSlot)
    if not (srcSlot and dstSlot and _G.TaxiNodePosition and _G.NumTaxiNodes) then
        return nil
    end
    local ok1, sx, sy = pcall(_G.TaxiNodePosition, srcSlot)
    local ok2, dx, dy = pcall(_G.TaxiNodePosition, dstSlot)
    local nsx = ok1 and ((Safe and Safe.Number) and Safe.Number(sx) or nil) or nil
    local nsy = ok1 and ((Safe and Safe.Number) and Safe.Number(sy) or nil) or nil
    local ndx = ok2 and ((Safe and Safe.Number) and Safe.Number(dx) or nil) or nil
    local ndy = ok2 and ((Safe and Safe.Number) and Safe.Number(dy) or nil) or nil
    if not (nsx and nsy and ndx and ndy) then
        return nil
    end
    local targetDist = math.sqrt((ndx - nsx) * (ndx - nsx) + (ndy - nsy) * (ndy - nsy))
    if targetDist <= 0.0005 then
        return nil
    end
    -- Calibrate seconds per normalized map unit against known routes on this continent.
    local sumSec = 0
    local sumDist = 0
    if currentNodeID and BASE_FLIGHT_TIMES[currentNodeID] then
        local okCnt, cnt = pcall(_G.NumTaxiNodes)
        local n = okCnt and ((Safe and Safe.Number) and Safe.Number(cnt) or nil) or 0
        for s = 1, n do
            local nid = slotToNodeID[s]
            local knownSec = nid and BASE_FLIGHT_TIMES[currentNodeID][nid]
            if type(knownSec) == "number" and knownSec > 0 then
                local okP, px, py = pcall(_G.TaxiNodePosition, s)
                local npx = okP and ((Safe and Safe.Number) and Safe.Number(px) or nil) or nil
                local npy = okP and ((Safe and Safe.Number) and Safe.Number(py) or nil) or nil
                if npx and npy then
                    local d = math.sqrt((npx - nsx) * (npx - nsx) + (npy - nsy) * (npy - nsy))
                    if d > 0.01 then
                        sumSec = sumSec + knownSec
                        sumDist = sumDist + d
                    end
                end
            end
        end
    end
    local rate = (sumDist > 0.02) and (sumSec / sumDist) or 920
    return math.max(10, math.floor((targetDist * rate) + 0.5))
end

--- Resolves display flight duration (seconds) and precision flag ("recorded" | "known" | "estimate").
function FlightTimes:ResolveDuration(srcID, dstID, dstSlot)
    if srcID and dstID then
        local saved = GetSavedTimesTable()
        local custom = saved and saved[srcID] and saved[srcID][dstID]
        if type(custom) == "number" and custom > 0 then
            return BaseToDisplaySeconds(custom), "recorded"
        end
        local base = BASE_FLIGHT_TIMES[srcID] and BASE_FLIGHT_TIMES[srcID][dstID]
        if type(base) == "number" and base > 0 then
            return BaseToDisplaySeconds(base), "known"
        end
        -- Sum exact Blizzard route hops when a direct/continuous entry isn't in BASE_FLIGHT_TIMES.
        if dstSlot and _G.GetNumRoutes and _G.TaxiGetNodeSlot then
            local okR, numRoutes = pcall(_G.GetNumRoutes, dstSlot)
            local nr = okR and ((Safe and Safe.Number) and Safe.Number(numRoutes) or nil) or nil
            if nr and nr >= 2 and nr <= 12 then
                local hopIDs = { srcID }
                local hopsOk = true
                for hop = 2, nr do
                    local okH, hopSlot = pcall(_G.TaxiGetNodeSlot, dstSlot, hop, true)
                    local hs = okH and ((Safe and Safe.Number) and Safe.Number(hopSlot) or nil) or nil
                    local hid = hs and ResolveNodeID(hs) or nil
                    if not hid then
                        hopsOk = false
                        break
                    end
                    hopIDs[#hopIDs + 1] = hid
                end
                if hopsOk then
                    hopIDs[#hopIDs + 1] = dstID
                    local total = 0
                    local allLegsOk = true
                    for i = 1, #hopIDs - 1 do
                        local leg = LookupDirectLegSeconds(hopIDs[i], hopIDs[i + 1])
                        if not leg then
                            allLegsOk = false
                            break
                        end
                        total = total + leg
                    end
                    if allLegsOk and total > 0 then
                        return BaseToDisplaySeconds(total), "estimate"
                    end
                end
            end
        end
        local graphTotal = FindShortestGraphDuration(srcID, dstID)
        if type(graphTotal) == "number" and graphTotal > 0 then
            return BaseToDisplaySeconds(graphTotal), "estimate"
        end
    end
    if currentSlot and dstSlot and currentSlot ~= dstSlot then
        local distEst = EstimateByMapDistance(currentSlot, dstSlot)
        if distEst then
            return BaseToDisplaySeconds(distEst), "estimate"
        end
    end
    return nil, nil
end

local function TooltipAlreadyHasFlightTime(tooltip)
    if not (tooltip and tooltip.NumLines) then
        return false
    end
    local tipName = tooltip.GetName and tooltip:GetName() or nil
    if not tipName then
        return false
    end
    local wantLabel = L["Flight time:"]
    local okN, numLines = pcall(tooltip.NumLines, tooltip)
    local n = okN and ((Safe and Safe.Number) and Safe.Number(numLines) or nil) or 0
    for i = 1, math.min(n, 20) do
        local leftObj = _G[tipName .. "TextLeft" .. i]
        if leftObj and leftObj.GetText then
            local okT, txt = pcall(leftObj.GetText, leftObj)
            local clean = okT and ((Safe and Safe.String) and Safe.String(txt) or (type(txt) == "string" and txt or nil)) or nil
            if clean == wantLabel then
                return true
            end
        end
    end
    return false
end

local function AppendFlightTimeToTooltip(dstID, dstSlot)
    if not IsFeatureEnabled() then
        return
    end
    local tooltip = _G.GameTooltip
    if not (tooltip and tooltip.IsShown and tooltip:IsShown()) then
        return
    end
    if TooltipAlreadyHasFlightTime(tooltip) then
        return
    end
    if not currentNodeID and not currentSlot then
        RefreshTaxiSlotCache()
    end
    local seconds, quality = FlightTimes:ResolveDuration(currentNodeID, dstID, dstSlot)
    if not seconds then
        return
    end
    local formatted = FormatDuration(seconds)
    if not formatted then
        return
    end
    local rightText = (quality == "estimate") and ("~" .. formatted) or formatted
    local rr, rg, rb = 1.0, 1.0, 1.0
    if quality == "estimate" then
        rr, rg, rb = 0.84, 0.92, 1.0
    end
    tooltip:AddDoubleLine(L["Flight time:"], rightText, 1.0, 0.82, 0.0, rr, rg, rb)
    tooltip:Show()
end

local function HandleTaxiSlotHover(slot)
    if not (slot and IsFeatureEnabled()) then
        return
    end
    if _G.TaxiNodeGetType then
        local okT, nodeType = pcall(_G.TaxiNodeGetType, slot)
        if not okT or not IsReachableState(nodeType) then
            return
        end
    end
    if not currentNodeID and not currentSlot then
        RefreshTaxiSlotCache()
    end
    local dstID = ResolveNodeID(slot)
    AppendFlightTimeToTooltip(dstID, slot)
end

local function HookFlightMapPin(pin)
    if not pin or hookedWidgets[pin] then
        return
    end
    if pin.IsForbidden then
        local okF, forb = pcall(pin.IsForbidden, pin)
        if not okF or forb then
            return
        end
    end
    if type(pin.HookScript) ~= "function" then
        return
    end
    hookedWidgets[pin] = true
    pin:HookScript("OnEnter", function(selfPin)
        if not IsFeatureEnabled() then
            return
        end
        local data = selfPin.taxiNodeData
        if type(data) ~= "table" or not IsReachableState(data.state) then
            return
        end
        if not currentNodeID and not currentSlot then
            RefreshTaxiSlotCache()
        end
        local dstID = (Safe and Safe.Number) and Safe.Number(data.nodeID) or nil
        local dstSlot = (Safe and Safe.Number) and Safe.Number(data.slotIndex) or nil
        AppendFlightTimeToTooltip(dstID, dstSlot)
    end)
end

local function HookActiveTaxiControls()
    local found = 0
    local fmf = _G.FlightMapFrame
    if fmf and type(fmf.pinPools) == "table" then
        for _, pool in pairs(fmf.pinPools) do
            if type(pool) == "table" and type(pool.EnumerateActive) == "function" then
                for first, second in pool:EnumerateActive() do
                    local pin = (type(first) == "table" or type(first) == "userdata") and first or second
                    if pin and pin.taxiNodeData then
                        HookFlightMapPin(pin)
                        found = found + 1
                    end
                end
            end
        end
    end

    if _G.NumTaxiNodes then
        local okCnt, cnt = pcall(_G.NumTaxiNodes)
        local n = okCnt and ((Safe and Safe.Number) and Safe.Number(cnt) or nil) or 0
        for i = 1, n do
            local btn = _G["TaxiButton" .. i]
            if btn and btn.HookScript then
                local isForb = false
                if btn.IsForbidden then
                    local okForb, fVal = pcall(btn.IsForbidden, btn)
                    isForb = (not okForb) or (fVal == true)
                end
                if not isForb then
                    found = found + 1
                    if not hookedWidgets[btn] then
                        hookedWidgets[btn] = true
                        btn:HookScript("OnEnter", function(selfBtn)
                            local slot = selfBtn.GetID and selfBtn:GetID() or nil
                            HandleTaxiSlotHover(slot)
                        end)
                    end
                end
            end
        end
    end
    return found
end

local function OnFlightMapRefresh()
    RefreshTaxiSlotCache()
    HookActiveTaxiControls()
end

local function EnsureFlightMapHooks()
    if _G.TaxiFrame and not hookedWidgets[_G.TaxiFrame] and _G.TaxiFrame.HookScript then
        hookedWidgets[_G.TaxiFrame] = true
        _G.TaxiFrame:HookScript("OnShow", OnFlightMapRefresh)
    end
    if _G.FlightMapFrame and not hookedWidgets[_G.FlightMapFrame] then
        hookedWidgets[_G.FlightMapFrame] = true
        if type(_G.FlightMapFrame.SetMapID) == "function" then
            hooksecurefunc(_G.FlightMapFrame, "SetMapID", OnFlightMapRefresh)
        end
        if type(_G.FlightMapFrame.HookScript) == "function" then
            _G.FlightMapFrame:HookScript("OnShow", OnFlightMapRefresh)
        end
    end
    if not loadUiHookInstalled and type(_G.FlightMap_LoadUI) == "function" then
        loadUiHookInstalled = true
        hooksecurefunc("FlightMap_LoadUI", function()
            EnsureFlightMapHooks()
            OnFlightMapRefresh()
        end)
    end
end

local function ClearSavedActiveFlight()
    if ns.db and ns.db.activeFlightTimer ~= nil then
        ns.db.activeFlightTimer = nil
    end
end

local function PersistActiveFlight(info)
    if not (ns.db and type(info) == "table") then
        return
    end
    local curCharKey = (Compat and Compat.CharacterKey and Compat.CharacterKey()) or nil
    ns.db.activeFlightTimer = {
        charKey = curCharKey,
        srcID = info.srcID,
        dstID = info.dstID,
        srcName = info.srcName,
        dstName = info.dstName,
        estSec = info.estSec,
        quality = info.quality,
        startedUnix = info.startedUnix,
        canSave = info.canSave == true,
    }
end

local function GetFlightClockColors()
    local Theme = ns.Theme
    local p = Theme and Theme.GetPalette and Theme:GetPalette() or nil
    local gold = (p and (p.textGold or p.accent)) or { 1.0, 0.82, 0.24, 1.0 }
    local text = (p and p.text) or { 0.94, 0.95, 0.98, 1.0 }
    local muted = (p and p.textMuted) or { 0.66, 0.72, 0.80, 1.0 }
    local accent = (p and p.accent) or { 0.35, 0.78, 1.0, 1.0 }
    return p, gold, text, muted, accent
end

local function ApplyTimerBarTheme()
    local f = timerBar
    if not f then
        return
    end
    local Theme = ns.Theme
    local p, gold, text, muted, accent = GetFlightClockColors()
    if Theme and Theme.ApplyBackdrop then
        Theme:ApplyBackdrop(f, "window", p)
    end
    if f.topRule then
        f.topRule:SetColorTexture(gold[1], gold[2], gold[3], 0.88)
    end
    if f.crestBox and Theme and Theme.ApplyBackdrop then
        Theme:ApplyBackdrop(f.crestBox, "inset", p)
    end
    if f.destFs then
        f.destFs:SetTextColor(text[1], text[2], text[3], 1.0)
    end
    if f.routeFs then
        f.routeFs:SetTextColor(muted[1], muted[2], muted[3], 1.0)
    end
    if f.statusBar then
        if demoFlightActive or not (activeFlightInfo and activeFlightInfo.quality == "estimate") then
            f.statusBar:SetStatusBarColor(gold[1], gold[2], gold[3], 0.95)
        else
            f.statusBar:SetStatusBarColor(accent[1], accent[2], accent[3], 0.95)
        end
    end
    if f.helpBtn and f.helpBtn.RefreshTheme then
        f.helpBtn:RefreshTheme()
    end
    if f.closeBtn and Theme and Theme.StyleButton then
        Theme:StyleButton(f.closeBtn, "danger")
    end
    f._lastRenderedTimeStr = nil
    f._lastTimeColorTag = nil
    f._lastBarColTag = nil
end

local function GetTimerDisplayMetrics()
    local nowMono = (GetTime and GetTime()) or 0
    if demoFlightActive then
        local elapsed = math.max(0, nowMono - (demoFlightStartAt or nowMono))
        if elapsed >= demoFlightEstSec then
            demoFlightStartAt = nowMono - 63
            elapsed = 63
        end
        return true, elapsed, demoFlightEstSec, "known", "Vento Bravo", "Karrath, Ermos"
    end
    if activeFlightInfo then
        local elapsed = math.max(0, nowMono - (activeFlightInfo.startedMono or nowMono))
        return true, elapsed, activeFlightInfo.estSec, activeFlightInfo.quality, activeFlightInfo.srcName, activeFlightInfo.dstName
    end
    return false, 0, nil, nil, nil, nil
end

local function UpdateTimerBarContent()
    local f = timerBar
    if not f then
        return
    end
    local valid, elapsed, estSec, quality, srcName, dstName = GetTimerDisplayMetrics()
    if not valid then
        return
    end

    local _, gold, _, muted, accent = GetFlightClockColors()
    local rawDest = (type(dstName) == "string" and dstName ~= "") and dstName or L["In Flight"]
    local destStr = rawDest
    if #rawDest > 22 then
        local shortHead = rawDest:match("^([^,]+),")
        if shortHead and shortHead ~= "" then
            destStr = shortHead:match("^%s*(.-)%s*$") or shortHead
        end
    end
    if f._lastRenderedDestStr ~= destStr then
        f._lastRenderedDestStr = destStr
        f.destFs:SetText(destStr)
    end

    local routeStr
    if type(srcName) == "string" and srcName ~= "" and srcName ~= rawDest then
        local shortSrc = srcName:match("^([^,]+),") or srcName
        shortSrc = shortSrc:match("^%s*(.-)%s*$") or shortSrc
        routeStr = shortSrc .. " -> " .. rawDest
    elseif quality == "estimate" then
        routeStr = L["Estimated arrival"]
    elseif quality == "recorded" then
        routeStr = L["Exact recorded route"]
    else
        routeStr = L["In Flight"]
    end
    if f._lastRenderedRouteStr ~= routeStr then
        f._lastRenderedRouteStr = routeStr
        f.routeFs:SetText(routeStr)
    end

    local isEstimated = (quality == "estimate")
    local timeStr
    local fillPct = 0.02
    local tr, tg, tb = gold[1], gold[2], gold[3]
    local br, bg, bb = tr, tg, tb

    if type(estSec) == "number" and estSec > 0 then
        local rem = estSec - elapsed
        if rem > 0.05 then
            local remStr = FormatDuration(math.ceil(rem)) or "1s"
            timeStr = isEstimated and ("~" .. remStr) or remStr
            fillPct = math.min(1.0, math.max(0.02, elapsed / estSec))
            if isEstimated then
                tr, tg, tb = 0.84, 0.92, 1.0
                br, bg, bb = accent[1], accent[2], accent[3]
            end
        else
            timeStr = L["Arriving soon..."]
            fillPct = 1.0
            tr, tg, tb = 1.0, 0.68, 0.25
            br, bg, bb = 1.0, 0.68, 0.25
        end
    else
        timeStr = FormatDuration(math.max(1, math.floor(elapsed + 0.5))) or "1s"
        fillPct = 0.45 + 0.40 * math.sin(elapsed * 2.2)
        tr, tg, tb = muted[1], muted[2], muted[3]
        br, bg, bb = accent[1], accent[2], accent[3]
    end

    if f._lastRenderedTimeStr ~= timeStr or f._lastTimeColorTag ~= (tostring(tr) .. ":" .. tostring(tg)) then
        f._lastRenderedTimeStr = timeStr
        f._lastTimeColorTag = tostring(tr) .. ":" .. tostring(tg)
        f.timeFs:SetText(timeStr)
        f.timeFs:SetTextColor(tr, tg, tb, 1.0)
    end
    if f.statusBar then
        f.statusBar:SetValue(fillPct)
        if f._lastBarColTag ~= f._lastTimeColorTag then
            f._lastBarColTag = f._lastTimeColorTag
            f.statusBar:SetStatusBarColor(br, bg, bb, 0.95)
        end
    end
end

local function StopTimerOnUpdate(f)
    if not f then
        return
    end
    f:SetScript("OnUpdate", nil)
    f._scOnUpdateActive = false
end

local function SyncTimerOnUpdate(f)
    if not f then
        return
    end
    if not f:IsShown() then
        StopTimerOnUpdate(f)
        return
    end
    if not f._scOnUpdateFn then
        f._scOnUpdateElapsed = 0
        f._scOnUpdateFn = function(selfFrame, dt)
            if not (demoFlightActive or activeFlightInfo) then
                StopTimerOnUpdate(selfFrame)
                selfFrame:Hide()
                return
            end
            selfFrame._scOnUpdateElapsed = (selfFrame._scOnUpdateElapsed or 0) + (dt or 0)
            if selfFrame._scOnUpdateElapsed < 0.1 then
                return
            end
            selfFrame._scOnUpdateElapsed = 0
            UpdateTimerBarContent()
        end
    end
    if not f._scOnUpdateActive then
        f._scOnUpdateElapsed = 0
        f._scOnUpdateActive = true
        f:SetScript("OnUpdate", f._scOnUpdateFn)
    end
end

local function EnsureTimerBar()
    if timerBar then
        return timerBar
    end
    local Theme = ns.Theme
    local uiParent = _G.UIParent
    local f = CreateFrame("Frame", "SocialCentralFlightTimerFrame", uiParent, "BackdropTemplate")
    f:SetSize(TIMER_BAR_W, TIMER_BAR_H)
    f:SetPoint("TOP", uiParent, "TOP", 0, -18)
    f:SetFrameStrata("HIGH")
    f:SetFrameLevel(85)
    f:SetClampedToScreen(true)
    if f.SetClipsChildren then
        f:SetClipsChildren(true)
    end

    local topRule = f:CreateTexture(nil, "OVERLAY", nil, 3)
    topRule:SetHeight(2)
    topRule:SetPoint("TOPLEFT", f, "TOPLEFT", 2, -1)
    topRule:SetPoint("TOPRIGHT", f, "TOPRIGHT", -2, -1)
    f.topRule = topRule

    local crestBox = CreateFrame("Frame", nil, f, "BackdropTemplate")
    crestBox:SetSize(28, 28)
    crestBox:SetPoint("TOPLEFT", f, "TOPLEFT", 7, -6)
    f.crestBox = crestBox

    local icon = crestBox:CreateTexture(nil, "ARTWORK")
    icon:SetPoint("TOPLEFT", crestBox, "TOPLEFT", 2, -2)
    icon:SetPoint("BOTTOMRIGHT", crestBox, "BOTTOMRIGHT", -2, 2)
    icon:SetTexture(ICON_FLIGHT_GRYPHON)
    icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    f.icon = icon

    local closeBtn
    if Theme and Theme.CreateButton then
        closeBtn = Theme:CreateButton(f, 18, 18, "X", "danger")
    else
        closeBtn = CreateFrame("Button", nil, f, "UIPanelCloseButton")
        closeBtn:SetSize(18, 18)
    end
    closeBtn:SetPoint("TOPRIGHT", f, "TOPRIGHT", -5, -5)
    closeBtn:SetFrameLevel(f:GetFrameLevel() + 12)
    closeBtn:SetScript("OnClick", function()
        if demoFlightActive then
            demoFlightActive = false
        else
            barDismissedForFlight = true
        end
        StopTimerOnUpdate(f)
        f:Hide()
    end)
    f.closeBtn = closeBtn

    local rightTextAnchor = closeBtn
    if Theme and Theme.CreateHelpButton then
        local helpBtn = Theme:CreateHelpButton(
            f,
            L["Help: Flight Countdown Bar"],
            L["Displays a compact live countdown bar at the top of the screen whenever you fly with a Flight Master, showing the destination, remaining arrival time, and progress bar."],
            L["Drag the countdown bar to reposition it anywhere, click '?' for help, or click X to hide it for the current flight only (flight time recording continues automatically)."],
            18,
            { target = f }
        )
        helpBtn:SetPoint("RIGHT", closeBtn, "LEFT", -3, 0)
        helpBtn:SetFrameLevel(closeBtn:GetFrameLevel())
        f.helpBtn = helpBtn
        rightTextAnchor = helpBtn
    end

    local timeFs = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    timeFs:SetPoint("TOPRIGHT", rightTextAnchor, "TOPLEFT", -6, -1)
    timeFs:SetJustifyH("RIGHT")
    timeFs:SetWordWrap(false)
    f.timeFs = timeFs

    local destFs = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    destFs:SetPoint("TOPLEFT", crestBox, "TOPRIGHT", 7, 0)
    destFs:SetPoint("TOPRIGHT", timeFs, "TOPLEFT", -6, 0)
    destFs:SetJustifyH("LEFT")
    destFs:SetWordWrap(false)
    f.destFs = destFs

    local routeFs = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    routeFs:SetPoint("BOTTOMLEFT", crestBox, "BOTTOMRIGHT", 7, 1)
    routeFs:SetPoint("RIGHT", f, "RIGHT", -8, 0)
    routeFs:SetJustifyH("LEFT")
    routeFs:SetWordWrap(false)
    f.routeFs = routeFs

    local trackBg = f:CreateTexture(nil, "BACKGROUND", nil, 1)
    trackBg:SetHeight(4)
    trackBg:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 6, 4)
    trackBg:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -6, 4)
    trackBg:SetColorTexture(0.02, 0.03, 0.04, 0.72)

    local sb = CreateFrame("StatusBar", nil, f)
    sb:SetPoint("TOPLEFT", trackBg, "TOPLEFT", 0, 0)
    sb:SetPoint("BOTTOMRIGHT", trackBg, "BOTTOMRIGHT", 0, 0)
    sb:SetStatusBarTexture(WHITE8X8_TEX)
    sb:SetMinMaxValues(0, 1)
    sb:SetValue(0)
    sb:SetFrameLevel(f:GetFrameLevel() + 4)
    f.statusBar = sb

    f:SetScript("OnEnter", function(selfFrame)
        if selfFrame._scDragging or not _G.GameTooltip then
            return
        end
        local valid, elapsed, estSec, quality, srcName, dstName = GetTimerDisplayMetrics()
        if not valid then
            return
        end
        _G.GameTooltip:SetOwner(selfFrame, "ANCHOR_BOTTOM")
        _G.GameTooltip:ClearLines()
        _G.GameTooltip:AddLine(dstName or L["In Flight"], 1.0, 0.85, 0.25)
        if type(srcName) == "string" and srcName ~= "" and srcName ~= dstName then
            _G.GameTooltip:AddLine(srcName .. " -> " .. (dstName or ""), 0.88, 0.91, 0.96, true)
        end
        if type(estSec) == "number" and estSec > 0 then
            local rem = math.max(0, math.ceil(estSec - elapsed))
            local remTxt = (rem > 0) and (FormatDuration(rem) or "1s") or L["Arriving soon..."]
            local totTxt = FormatDuration(estSec) or "-"
            local elTxt = FormatDuration(math.max(1, math.floor(elapsed + 0.5))) or "1s"
            _G.GameTooltip:AddDoubleLine(L["Route duration"], (quality == "estimate" and "~" or "") .. totTxt, 0.72, 0.78, 0.86, 1.0, 1.0, 1.0)
            _G.GameTooltip:AddDoubleLine(L["Remaining: %s"]:format(remTxt), L["Elapsed: %s"]:format(elTxt), 0.35, 0.92, 0.62, 0.76, 0.82, 0.90)
        else
            local elTxt = FormatDuration(math.max(1, math.floor(elapsed + 0.5))) or "1s"
            _G.GameTooltip:AddLine(L["Elapsed: %s"]:format(elTxt), 0.88, 0.91, 0.96, true)
        end
        _G.GameTooltip:AddLine(L["Drag to move · Click X to hide this flight"], 0.62, 0.70, 0.80, true)
        _G.GameTooltip:Show()
    end)
    f:SetScript("OnLeave", function()
        if _G.GameTooltip then
            _G.GameTooltip:Hide()
        end
    end)

    if Theme and Theme.MakeMovable then
        Theme:MakeMovable(f, {
            key = "flight_timer",
            anchor = "TOP",
            combatLock = false,
            handles = { f },
            onStart = function()
                if _G.GameTooltip and _G.GameTooltip:IsOwned(f) then
                    _G.GameTooltip:Hide()
                end
            end,
            onReset = function(win)
                win:ClearAllPoints()
                win:SetPoint("TOP", _G.UIParent, "TOP", 0, -18)
            end,
        })
    end

    f:HookScript("OnShow", function(selfFrame)
        ApplyTimerBarTheme()
        UpdateTimerBarContent()
        SyncTimerOnUpdate(selfFrame)
    end)
    f:HookScript("OnHide", function(selfFrame)
        StopTimerOnUpdate(selfFrame)
    end)

    f:Hide()
    timerBar = f
    ApplyTimerBarTheme()
    return f
end

local function ShowTimerBarIfAllowed()
    if not demoFlightActive then
        if not IsTimerBarEnabled() then
            if timerBar and timerBar:IsShown() then
                timerBar:Hide()
            end
            return
        end
        if not activeFlightInfo or barDismissedForFlight then
            return
        end
    end
    local f = EnsureTimerBar()
    if f:IsShown() then
        ApplyTimerBarTheme()
        UpdateTimerBarContent()
        SyncTimerOnUpdate(f)
    else
        f:Show()
    end
end

local function HideTimerBar()
    if timerBar then
        StopTimerOnUpdate(timerBar)
        if timerBar:IsShown() then
            timerBar:Hide()
        end
    end
end

local function ResolveTaxiNodeDisplayName(slot)
    if not (slot and _G.TaxiNodeName) then
        return nil
    end
    local okNm, nm = pcall(_G.TaxiNodeName, slot)
    if not okNm then
        return nil
    end
    local clean = (Safe and Safe.String) and Safe.String(nm) or (type(nm) == "string" and nm or nil)
    if clean and clean ~= "" then
        return clean
    end
    return nil
end

local function StopFlightRecording()
    if flightTicker then
        flightTicker:Cancel()
        flightTicker = nil
    end
    pendingSrcID = nil
    pendingDstID = nil
    pendingSince = nil
    flightStartAt = nil
    confirmedOnTaxi = false
    pendingSrcName = nil
    pendingDstName = nil
    pendingEstSec = nil
    pendingQuality = nil
    pendingCanSave = false
    activeFlightInfo = nil
    barDismissedForFlight = false
    ClearSavedActiveFlight()
    if not demoFlightActive then
        HideTimerBar()
    end
end

local function IsPlayerOnTaxi()
    if type(_G.UnitOnTaxi) ~= "function" then
        return nil
    end
    local ok, val = pcall(_G.UnitOnTaxi, "player")
    if not ok then
        return nil
    end
    if Safe and Safe.IsSecret and Safe.IsSecret(val) then
        return nil
    end
    return val == true
end

local function ActivateCountdownNow(nowMono)
    flightStartAt = nowMono
    confirmedOnTaxi = true
    pendingSince = nil
    barDismissedForFlight = false
    activeFlightInfo = {
        srcID = pendingSrcID,
        dstID = pendingDstID,
        srcName = pendingSrcName,
        dstName = pendingDstName,
        estSec = pendingEstSec,
        quality = pendingQuality,
        startedMono = nowMono,
        startedUnix = time(),
        canSave = pendingCanSave,
    }
    PersistActiveFlight(activeFlightInfo)
    ShowTimerBarIfAllowed()
end

local function SaveCompletedFlight()
    local abortedMidFlight = false
    if _G.UnitIsDeadOrGhost then
        local okDead, isDead = pcall(_G.UnitIsDeadOrGhost, "player")
        if okDead and Safe and Safe.Value and Safe.Value(isDead) == true then
            abortedMidFlight = true
        end
    end
    if not abortedMidFlight and _G.IsInInstance then
        local okInst, inInst = pcall(_G.IsInInstance)
        if okInst and Safe and Safe.Value and Safe.Value(inInst) == true then
            abortedMidFlight = true
        end
    end
    if abortedMidFlight or not (flightStartAt and pendingCanSave and pendingSrcID and pendingDstID and pendingSrcID ~= pendingDstID) then
        StopFlightRecording()
        return
    end
    local elapsed = math.ceil((GetTime and GetTime() or 0) - flightStartAt)
    local baseSec = ActualToBaseSeconds(elapsed)
    if baseSec and baseSec >= 5 and baseSec <= 3600 then
        local saved = GetSavedTimesTable()
        if saved then
            saved[pendingSrcID] = saved[pendingSrcID] or {}
            saved[pendingSrcID][pendingDstID] = baseSec
        end
    end
    StopFlightRecording()
end

local function PollFlightRecorder()
    local now = (GetTime and GetTime()) or 0
    local onTaxi = IsPlayerOnTaxi()
    if pendingSince and not flightStartAt then
        if onTaxi == true then
            ActivateCountdownNow(now)
        elseif (now - pendingSince) > TAKEOFF_TIMEOUT_SEC then
            StopFlightRecording()
            return
        end
    elseif flightStartAt then
        if onTaxi == true then
            confirmedOnTaxi = true
        elseif onTaxi == false and confirmedOnTaxi then
            SaveCompletedFlight()
            return
        elseif (now - flightStartAt) > 3600 then
            StopFlightRecording()
            return
        end
    else
        StopFlightRecording()
    end
end

local function BeginFlightRecording(slot)
    StopFlightRecording()
    if not (currentNodeID or currentSlot) then
        RefreshTaxiSlotCache()
    end
    local dstID = ResolveNodeID(slot)
    local dstName = ResolveTaxiNodeDisplayName(slot)
    local srcName = ResolveTaxiNodeDisplayName(currentSlot)
        or (Compat and Compat.CurrentZoneName and Compat.CurrentZoneName())
        or nil
    local estSec, quality = FlightTimes:ResolveDuration(currentNodeID, dstID, slot)
    pendingSrcID = currentNodeID
    pendingDstID = dstID
    pendingSrcName = srcName
    pendingDstName = dstName
    pendingEstSec = estSec
    pendingQuality = quality
    pendingCanSave = (currentNodeID ~= nil and dstID ~= nil and currentNodeID ~= dstID)
    pendingSince = (GetTime and GetTime()) or 0
    flightStartAt = nil
    confirmedOnTaxi = false
    if _G.C_Timer and _G.C_Timer.NewTicker then
        flightTicker = _G.C_Timer.NewTicker(FLIGHT_POLL_INTERVAL, PollFlightRecorder)
    end
end

local function TryResumeMidFlightFromSaved()
    if activeFlightInfo or pendingSince then
        return
    end
    local saved = ns.db and ns.db.activeFlightTimer
    if type(saved) ~= "table" then
        return
    end
    local curCharKey = (Compat and Compat.CharacterKey and Compat.CharacterKey()) or nil
    if saved.charKey and curCharKey and saved.charKey ~= curCharKey then
        return
    end
    local onTaxi = IsPlayerOnTaxi()
    if onTaxi ~= true then
        ClearSavedActiveFlight()
        return
    end
    local elapsedUnix = math.max(0, time() - (tonumber(saved.startedUnix) or 0))
    local maxReasonable = (tonumber(saved.estSec) or 1800) + 180
    local nowMono = (GetTime and GetTime()) or 0
    local isExpired = (elapsedUnix > maxReasonable)
    if isExpired then
        ClearSavedActiveFlight()
    end
    pendingSrcID = saved.srcID
    pendingDstID = saved.dstID
    pendingSrcName = saved.srcName
    pendingDstName = saved.dstName
    pendingEstSec = isExpired and nil or saved.estSec
    pendingQuality = isExpired and nil or saved.quality
    pendingCanSave = (not isExpired) and (saved.canSave == true)
    flightStartAt = isExpired and nowMono or (nowMono - elapsedUnix)
    confirmedOnTaxi = true
    activeFlightInfo = {
        srcID = saved.srcID,
        dstID = saved.dstID,
        srcName = saved.srcName,
        dstName = saved.dstName,
        estSec = pendingEstSec,
        quality = pendingQuality,
        startedMono = flightStartAt,
        startedUnix = isExpired and time() or saved.startedUnix,
        canSave = pendingCanSave,
    }
    if _G.C_Timer and _G.C_Timer.NewTicker then
        flightTicker = _G.C_Timer.NewTicker(FLIGHT_POLL_INTERVAL, PollFlightRecorder)
    end
    ShowTimerBarIfAllowed()
end

function FlightTimes:RefreshTimerVisibility()
    if demoFlightActive then
        ShowTimerBarIfAllowed()
        return
    end
    if activeFlightInfo and not barDismissedForFlight and IsTimerBarEnabled() then
        ShowTimerBarIfAllowed()
    else
        HideTimerBar()
    end
end

function FlightTimes:SetDemoPreview(enabled)
    if enabled then
        demoFlightActive = true
        demoFlightStartAt = ((GetTime and GetTime()) or 0) - 63
        ShowTimerBarIfAllowed()
    else
        demoFlightActive = false
        if activeFlightInfo and not barDismissedForFlight and IsTimerBarEnabled() then
            ShowTimerBarIfAllowed()
        else
            HideTimerBar()
        end
    end
end

function FlightTimes:Init()
    if self._initialized then
        return
    end
    self._initialized = true

    if not globalHooksInstalled then
        globalHooksInstalled = true
        if type(_G.TaxiNodeOnButtonEnter) == "function" then
            hooksecurefunc("TaxiNodeOnButtonEnter", function(btnOrSlot)
                local slot = (type(btnOrSlot) == "number") and btnOrSlot
                    or (btnOrSlot and btnOrSlot.GetID and btnOrSlot:GetID())
                    or nil
                HandleTaxiSlotHover(slot)
            end)
        end
        if type(_G.TakeTaxiNode) == "function" then
            hooksecurefunc("TakeTaxiNode", function(slot)
                BeginFlightRecording(slot)
            end)
        end
        if type(_G.TaxiRequestEarlyLanding) == "function" then
            hooksecurefunc("TaxiRequestEarlyLanding", StopFlightRecording)
        end
        if type(_G.AcceptBattlefieldPort) == "function" then
            hooksecurefunc("AcceptBattlefieldPort", function(_, accept)
                if accept and (flightStartAt or pendingSince) then
                    StopFlightRecording()
                end
            end)
        end
        if _G.C_SummonInfo and type(_G.C_SummonInfo.ConfirmSummon) == "function" then
            hooksecurefunc(_G.C_SummonInfo, "ConfirmSummon", StopFlightRecording)
        end
        if type(_G.AcceptProposal) == "function" then
            hooksecurefunc("AcceptProposal", StopFlightRecording)
        end
    end

    EnsureFlightMapHooks()

    ns.RegisterEvent(self, "TAXIMAP_OPENED", function()
        bindSeq = bindSeq + 1
        local seq = bindSeq
        local function TryBind(attempt)
            if seq ~= bindSeq then
                return
            end
            EnsureFlightMapHooks()
            RefreshTaxiSlotCache()
            if HookActiveTaxiControls() > 0 then
                return
            end
            if attempt < 2 and _G.C_Timer and _G.C_Timer.After then
                _G.C_Timer.After(0, function()
                    TryBind(attempt + 1)
                end)
            end
        end
        TryBind(0)
    end)

    ns.RegisterEvent(self, "PLAYER_CONTROL_LOST", function()
        if pendingSince and not flightStartAt and IsPlayerOnTaxi() == true then
            ActivateCountdownNow((GetTime and GetTime()) or 0)
        end
    end)

    ns.RegisterEvent(self, "PLAYER_CONTROL_GAINED", function()
        if flightStartAt then
            local onTaxi = IsPlayerOnTaxi()
            if onTaxi ~= true then
                SaveCompletedFlight()
            end
        end
    end)

    ns.RegisterEvent(self, "PLAYER_ENTERING_WORLD", function()
        if _G.C_Timer and _G.C_Timer.After then
            _G.C_Timer.After(0.6, TryResumeMidFlightFromSaved)
        else
            TryResumeMidFlightFromSaved()
        end
    end)

    ns:On("THEME_CHANGED", function()
        ApplyTimerBarTheme()
    end)

    ns:On("SETTINGS_UPDATED", function()
        FlightTimes:RefreshTimerVisibility()
    end)
end
