// App/presets.scd — the preset manager: ONE object for every preset of the
// project. presets/<kind>/<name>.scd, kind = project | mixer | matrix | <machine>.
// Every file is the same event literal; a kind only picks its sections (and a
// machine kind only its own entry of `layers`). Loads after lib + ui.

(
// ===== CONFIG — edit here ============================================
~cfg_presets = (
    root:    ((~appDir ? (thisProcess.nowExecutingPath !? (_.dirname))) ? "") +/+ "presets",
    kinds:   (
        project: [\layers, \mixer, \fx, \wander, \cells],
        mixer:   [\mixer, \fx],
        matrix:  [\wander, \cells]
    ),
    machine: [\layers],
    btnW:    84,
    btnH:    24,
    gap:     6
);


// ===== LOGIC =========================================================
~preset = (
    current: (),
    bars:    List.new,

    isMachine: { |self, kind| ~cfg_presets.kinds[kind].isNil },
    sectionsOf: { |self, kind|
        ~cfg_presets.kinds[kind] ?? { ~cfg_presets.machine }
    },
    layersOf: { |self, kind|
        if(self.isMachine(kind)) { [kind] } { ~netLayers.value }
    },
    dir: { |self, kind|
        var root = ~cfg_presets.root, d = root +/+ kind.asString;
        if(File.exists(root).not) { File.mkdir(root) };
        if(File.exists(d).not) { File.mkdir(d) };
        d
    },
    names: { |self, kind|
        (self.dir(kind) +/+ "*.scd").pathMatch
            .collect { |p| PathName(p).fileNameWithoutExtension }.sort
    },

    save: { |self, kind, name|
        var path, e = (), layers;
        kind = kind.asSymbol;
        layers = self.layersOf(kind);
        name = (name ? "").asString.stripWhiteSpace;
        if(name.isEmpty) { name = kind.asString ++ "_" ++ Date.getDate.stamp };
        path = self.dir(kind) +/+ (name ++ ".scd");
        self.sectionsOf(kind).do { |sec| e[sec] = self.sec[sec][\get].value(layers) };
        File.use(path, "w", { |f|
            f.write("// " ++ kind ++ " preset · " ++ name ++ " · " ++ Date.getDate.stamp ++ "\n"
                ++ e.asCompileString ++ "\n");
        });
        self.current[kind] = name;
        self.refresh(kind);
        ("preset saved -> " ++ path).postln;
        path
    },

    load: { |self, kind, name|
        var path, e, layers;
        kind = kind.asSymbol;
        layers = self.layersOf(kind);
        path = self.dir(kind) +/+ (name.asString ++ ".scd");
        e = if(File.exists(path)) { path.load };
        if(e.isKindOf(Event).not) { ("preset не найден или повреждён: " ++ path).warn; nil } {
            self.sectionsOf(kind).do { |sec|
                e[sec] !? { |v| self.sec[sec][\set].value(v, layers) };
            };
            if(kind == \project) { self.current = (project: name.asString) } {
                self.current[kind] = name.asString;
            };
            ~netChanged.value;
            ~netHooks.do { |f| f.(nil, nil, nil) };
            self.refresh(nil);
            ("preset loaded <- " ++ kind ++ "/" ++ path.basename).postln;
            e
        }
    },

    sec: (
        layers: (
            get: { |layers|
                var ls = ();
                layers.do { |l|
                    ~ungSpecOf.(l) !? { |spec|
                        var d = ();
                        spec.params.do { |p| d[p.key] = ~netGet.(l, p.key) };
                        ls[l] = d;
                    };
                };
                ls
            },
            set: { |ls, layers|
                ls.keysValuesDo { |l, vals|
                    if(layers.includes(l.asSymbol) and: { ~ungSpecOf.(l).notNil }) {
                        vals.keysValuesDo { |k, v| if(~netParam.(l, k).notNil) { ~setParam.(l, k, v) } };
                    };
                };
            }
        ),
        mixer: (
            get: {
                ~cfg_mixer !? { |m| (
                    master: m.master,
                    levels: m.levels.collect(_.copy),
                    muted:  (~mixMuted ? ()).keys.asArray.select { |l| ~mixMuted[l] == true },
                    solo:   ~mixSoloCur
                ) }
            },
            set: { |m|
                if(~mixSet.notNil) {
                    m[\levels] !? { |rows|
                        rows.keysValuesDo { |l, lv|
                            if((~mixerLayers ? []).includes(l.asSymbol)) {
                                lv.keysValuesDo { |which, v| ~mixSet.(l.asSymbol, which, v) };
                            };
                        };
                    };
                    m[\master] !? { |v| ~masterSet.(v) };
                    m[\muted] !? { |ml|
                        ~mixMuted = ();
                        ml.do { |l| ~mixMuted[l.asSymbol] = true };
                        ~mixSoloCur = m[\solo] !? (_.asSymbol);
                        ~mixApplyLevels.value;
                        ~mixerRefreshMute.value;
                        ~mixerRefreshSolo.value;
                    };
                };
            }
        ),
        fx: (
            get: {
                ~cfg_effects !? { |fx| (
                    rev_mode: fx.rev_mode, dly_mode: fx.dly_mode, bass: fx.rev_bass, treble: fx.rev_treble
                ) }
            },
            set: { |fx|
                if(~cfg_effects.notNil) {
                    [
                        [\rev_mode, \mode,   [\space_echo_rev], [\rev_mode]],
                        [\dly_mode, \mode,   [\space_echo_dly], [\dly_mode]],
                        [\bass,     \bass,   [\space_echo_rev, \space_echo_dly], [\rev_bass, \dly_bass]],
                        [\treble,   \treble, [\space_echo_rev, \space_echo_dly], [\rev_treble, \dly_treble]]
                    ].do { |row|
                        fx[row[0]] !? { |v|
                            row[2].do { |n| Ndef(n).set(row[1], v) };
                            row[3].do { |k| ~cfg_effects[k] = v };
                        };
                    };
                    ~mixerFx !? { |wid|
                        wid[\revMode] !? { |p| ~uiPopupSet.(p, (~cfg_effects.rev_mode - 1).clip(0, 11)) };
                        wid[\dlyMode] !? { |p| ~uiPopupSet.(p, (~cfg_effects.dly_mode - 1).clip(0, 11)) };
                        wid[\bass]    !? { |r| ~uiRulerSet.(r, ~cfg_effects.rev_bass) };
                        wid[\treble]  !? { |r| ~uiRulerSet.(r, ~cfg_effects.rev_treble) };
                        { wid[\dlyGlyph] !? (_.refresh); wid[\revGlyph] !? (_.refresh) }.defer;
                    };
                };
            }
        ),
        wander: (
            get: { [~cfg_net.wander, ~cfg_net.wanderRate] },
            set: { |w| ~netWander.(w[0], w[1]) }
        ),
        cells: (
            get: { ~netCells.values.asArray.collect { |c| c[\src] ++ c[\dst] ++ [c[\depth]] } },
            set: { |cs|
                ~netClear.(false);
                cs.do { |c| ~netPut.(c[0], c[1], c[2], c[3], c[4]) };
            }
        )
    ),

    // field and popup are two buttons wide: the bar sits on the button grid
    bar: { |self, parent, x, y, kind|
        var c = ~cfg_presets, fw = (c.btnW * 2) + c.gap, bx = x + fw + c.gap, y2 = y + c.btnH + c.gap;
        var b = (kind: kind.asSymbol), field;
        field = TextField(parent, Rect(x, y, fw, c.btnH)).string_("").font_(~uiMono.(11))
            .background_(~uiPal.paper).stringColor_(~uiPal.ink);
        b[\field] = field;
        b[\save] = ~uiBtn.(parent, Rect(bx, y, c.btnW, c.btnH), "save", {
            ~preset.save(b[\kind], field.string);
            field.string_("");
        });
        b[\pop] = ~uiPopup.(parent, Rect(x, y2, fw, c.btnH), [], -1, { });
        b[\load] = ~uiBtn.(parent, Rect(bx, y2, c.btnW, c.btnH), "load", {
            var p = b[\pop];
            if(p[\index] >= 0 and: { p[\index] < p[\items].size }) {
                ~preset.load(b[\kind], p[\items][p[\index]]);
            };
        });
        self.bars.add(b);
        self.sync(b);
        b
    },
    sync: { |self, b|
        var items = self.names(b[\kind]);
        b[\pop][\items] = items;
        b[\pop][\index] = items.indexOfEqual(self.current[b[\kind]]) ? -1;
        { b[\pop][\view].refresh }.defer;
    },
    refresh: { |self, kind|
        self.bars.removeAllSuchThat { |b| b[\field].isClosed };
        self.bars.do { |b| if(kind.isNil or: { b[\kind] == kind }) { self.sync(b) } };
    }
);

"presets — ~preset.save(kind, name) / ~preset.load(kind, name) / ~preset.bar(...)".postln;
)
