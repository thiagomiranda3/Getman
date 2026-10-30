// The two HTTP script hooks. Globals never survive a phase boundary.
enum ScriptPhase { preRequest, postResponse }
