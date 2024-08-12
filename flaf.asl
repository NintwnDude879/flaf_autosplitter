state("flaf-Win64-Shipping"){}

//Ran when autosplitter starts running (NOT when it starts counting time, but when it is functioning)
startup {
    #region Create settings
    settings.CurrentDefaultParent = null;
    settings.Add("Lap Split");
    settings.SetToolTip("Lap Split", "Splits on every lap completion");

    settings.CurrentDefaultParent = null;
    settings.Add("Map Split", true);
    settings.SetToolTip("Map Split", "Splits on every map completion");

    settings.CurrentDefaultParent = null;
    settings.Add("Unsupported version warning", true);
    #endregion
}

//Ran when game process is found
init {
    #region Set version (and a few variables)
        //Sets the version of the game upon startup
        int gameSize = modules.First().ModuleMemorySize;
        refreshRate = 60;

        switch (gameSize){
            default: {
                vars.version = 100; // Unsupported
                if (!settings["Unsupported version warning"]) break;
                MessageBox.Show("Sorry, it seems like the version of FLAF that you're using isn't currently fully supported! Splits may not work with this version of FLAF currently.\n\n"+
                "If this seems like a mistake, or you would like to suggest an additional version to support, please go to https://forms.gle/jxidK6RFToEXzUDe7 or contact nintendude_sr on Discord.\n\n"+
                "Below is the 'gameSize' variable. Please include this when contacting about the issue.\n"+
                "gameSize: 0x"+gameSize.ToString("X")+"\n\n"+
                "Sorry for the inconvenience.", "Warning: Version Not Supported", MessageBoxButtons.OK, MessageBoxIcon.Warning).ToString();
                print(gameSize.ToString("X"));
                break;
            }
            case 0x5428000: vars.version = 1.0; break;
        }
        print("Version: "+vars.version);

        const int CLASS_OFFSET = 0x10;
        const int CHILD_OFFSET = 0x50;
        const int NEXT_OFFSET = 0x20;
        const int NAME_OFFSET = 0x28;
        const int INTERNAL_OFFSET = 0x4C;
        const int SUPERFIELD_OFFSET = 0x40;
        vars.offsets = new Dictionary<string, int>();
        vars.fnames = new Dictionary<long, string>();
    #endregion

    #region Declare functions

        #region Sigscan adjacent/Unreal Engine introspection related funcs
            //Credit to Micrologist and Meta for this func, found in the Stray autosplitter
            vars.GetStaticPointerFromSig = (Func<string, int, IntPtr>) ( (signature, instructionOffset) => {
                var scanner = new SignatureScanner(game, modules.First().BaseAddress, (int)modules.First().ModuleMemorySize);
                var pattern = new SigScanTarget(signature);
                var location = scanner.Scan(pattern);
                if (location == IntPtr.Zero) return IntPtr.Zero;
                int offset = game.ReadValue<int>((IntPtr)location + instructionOffset);
                return (IntPtr)location + offset + instructionOffset + 0x4;
            });

            //Credit to Micrologist and Meta for this func, found in the Stray autosplitter
            vars.FNameToString = (Func<long, string>) ( longKey => {
                if (vars.fnames.ContainsKey(longKey)) return vars.fnames[longKey];
                int key = (int)(longKey & uint.MaxValue);
                int partial = (int)(longKey >> 32);
                int chunkOffset = key >> 16;
                int nameOffset = (ushort)key;
                IntPtr namePoolChunk = memory.ReadValue<IntPtr>((IntPtr)vars.FNamePool + (chunkOffset+2) * 0x8);
                Int16 nameEntry = game.ReadValue<Int16>((IntPtr)namePoolChunk + 2 * nameOffset);
                int nameLength = nameEntry >> 6;
                string output = game.ReadString((IntPtr)namePoolChunk + 2 * nameOffset + 2, nameLength);
                string outputParsed = (partial == 0) ? output : output + "_" + partial.ToString();
                vars.fnames[longKey] = outputParsed;
                return outputParsed;
            });

            //Credit to apple1417 for this function, not sure where else it was used but I found it in their Borderlands 3 ASL
            vars.GetPropertyOffset = (Func<IntPtr, string, IntPtr>) ((address, name) => {
                var _class = game.ReadPointer(address + CLASS_OFFSET);
                for (
                    ;
                    _class != IntPtr.Zero;
                    _class = game.ReadPointer(_class + SUPERFIELD_OFFSET)
                ){
                    for (IntPtr property = game.ReadPointer(_class + CHILD_OFFSET);
                        property != IntPtr.Zero;
                        property = game.ReadPointer(property + NEXT_OFFSET)
                    ){
                        string propName = vars.FNameToString(game.ReadValue<long>(property + NAME_OFFSET));
                        if (propName == name){
                            int offset = game.ReadValue<int>(property + INTERNAL_OFFSET);
                            print("Found property \""
                            + name
                            + "\" at offset 0x"
                            + offset.ToString("X")
                            );

                            vars.offsets[name] = offset;
                            return property;
                        }
                    }
                }

                print("Couldn't find property \""+name+"\".");
                return IntPtr.Zero;
            });

        #endregion
    #endregion

    #region Sigscanning
        vars.GEngine = vars.GetStaticPointerFromSig("48 8B 05 ????????"     //mov rax, [GEngine]
                                                   +"48 8B D1"              //mov rdx, rcx
                                                   +"48 8B 88 F8 0A 00 00"  //mov rcx, [rax+00000AF8]
                                                   +"48 85 C9"              //test rcx, rcx
                                                   , 3);

        //vars.FNamePool = vars.GetStaticPointerFromSig("", 0);

    #endregion

    vars.watchers = new MemoryWatcherList {
        new MemoryWatcher<int>(new DeepPointer(vars.GEngine, 0xD28, 0x38, 0x0, 0x30, 0x2A0, 0x350, 0xB8)) { Name = "laps" , FailAction = MemoryWatcher.ReadFailAction.SetZeroOrNull },
        new MemoryWatcher<int>(new DeepPointer(vars.GEngine, 0xD28, 0x38, 0x0, 0x30, 0x2A0, 0x350, 0xBC)) { Name = "trackTimeMillis" , FailAction = MemoryWatcher.ReadFailAction.SetZeroOrNull },
    };
}

//Ran forever, when true starts timer
start {
    if (vars.watchers["trackTimeMillis"].Current > 0 && vars.watchers["trackTimeMillis"].Old == 0) return true;
}

//Ran forever, when true resets timer
reset {

}

//Ran forever, when true pauses timer, when false unpauses
isLoading {

}

//Ran forever
update {
    vars.watchers.UpdateAll(game);
    if (vars.watchers["laps"].Current != vars.watchers["laps"].Old){
        print("Old: "+vars.watchers["laps"].Old.ToString());
        print("New: "+vars.watchers["laps"].Current.ToString());
    }
}

//Ran forever, when returns true splits
split {
    if (settings["Map Split"] && vars.watchers["laps"].Current == 6 && vars.watchers["laps"].Old == 5) return true;

    if (settings["Lap Split"] && vars.watchers["laps"].Current > vars.watchers["laps"].Old && vars.watchers["laps"].Current < 6 && vars.watchers["laps"].Current > 1) return true;
}