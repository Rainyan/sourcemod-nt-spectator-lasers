#pragma semicolon 1

//#define DEBUG_PROFILE

#if defined(DEBUG_PROFILE)
#include <profiler>
#endif

#include <sourcemod>
#include <sdktools>
#include <neotokyo>

#define PLUGIN_VERSION "0.3"

// The laser texture to use.
#define BEAM_ASSET "materials/sprites/purplelaser1.vmt"

#define NEO_MAX_PLAYERS 32
#define NEO_TEAM_SPECTATOR 1

static int spectators[NEO_MAX_PLAYERS], players[NEO_MAX_PLAYERS];
static int num_spectating = 0, num_playing = 0;

static int _beamModel;

//#define INCLUDE_TRIG_LOOKUP_TABLES

#if defined(INCLUDE_TRIG_LOOKUP_TABLES)
#define SINCOS_LOOKUP_DEGREE_ACCURACY 1.0
// This should equal 360 / (float)SINCOS_LOOKUP_DEGREE_ACCURACY
#define NUM_LOOKUP_ENTRIES 360
static float _sin_lookup_table[NUM_LOOKUP_ENTRIES], _cos_lookup_table[NUM_LOOKUP_ENTRIES];
static int _truncate_helper;
#endif

ConVar g_hCvar_BeamOffset_X = null, g_hCvar_BeamOffset_Y = null, g_hCvar_BeamOffset_Z = null;
ConVar g_hCvar_BeamWidth = null;
ConVar g_hCvar_BeamColor_R = null, g_hCvar_BeamColor_G = null, g_hCvar_BeamColor_B = null, g_hCvar_BeamColor_A = null;

#if defined(INCLUDE_TRIG_LOOKUP_TABLES)
ConVar g_hCvar_UseTrigLookup = null;
#endif

#if defined(DEBUG_PROFILE)
ConVar g_hCvar_ProfileOutput = null;
static Profiler _prof = null;
#endif

#if !defined(PI)
#define PI 3.14159265359
#endif

// SourcePawn Compiler 1.10 won't optimise this constant division,
// so pre-calculating it.
#define PI_OVER_180 0.01745329252

public Plugin myinfo = {
    name = "NT Spectator Lasers",
    description = "Draw laser lines for spectators to visualize which direction each player is aiming towards.",
    author = "Rain",
    version = PLUGIN_VERSION,
    url = "https://github.com/Rainyan/sourcemod-nt-spectator-lasers"
};

public void OnPluginStart()
{
#if defined(DEBUG_PROFILE)
    _prof = new Profiler();
#endif

#if defined(INCLUDE_TRIG_LOOKUP_TABLES)
    if (SINCOS_LOOKUP_DEGREE_ACCURACY <= 0 || SINCOS_LOOKUP_DEGREE_ACCURACY > 1) {
        SetFailState("SINCOS_LOOKUP_DEGREE_ACCURACY needs to be > 0.0 and <= 1.0");
    } else if (NUM_LOOKUP_ENTRIES != 360 * 1 / (SINCOS_LOOKUP_DEGREE_ACCURACY * 1.0)) {
        SetFailState("sin/cos lookup table allocation size mismatch");
    }

    _truncate_helper = RoundToNearest(1.0 / SINCOS_LOOKUP_DEGREE_ACCURACY);
    for (int i = 0; i < NUM_LOOKUP_ENTRIES; ++i) {
        float angle = /*-360 + */i * SINCOS_LOOKUP_DEGREE_ACCURACY;
        _sin_lookup_table[i] = Sine(angle * PI_OVER_180);
        _cos_lookup_table[i] = Cosine(angle * PI_OVER_180);
#if(0)
        PrintToServer("%d Angle (%f) * PI_OVER_180 (%f) ==> %f",
            i,
            angle,
            angle * PI_OVER_180,
            _sin_lookup_table[i]);
#endif
    }
    _sin_lookup_table[NUM_LOOKUP_ENTRIES / 2] = 0.0;
#endif

    HookEvent("player_death", Event_PlayerDeath);
    HookEvent("player_spawn", Event_PlayerSpawn);
    HookEvent("player_team", Event_PlayerTeam);

    for (int client = 1; client <= MaxClients; ++client) {
        if (IsClientConnected(client)) {
            int team = GetClientTeam(client);
            if (team == NEO_TEAM_SPECTATOR) {
                AddPlayerToArray(spectators, num_spectating, client);
            } else if (team > NEO_TEAM_SPECTATOR) { // teams Jin and NSF are > Spec
                AddPlayerToArray(players, num_playing, client);
            }
        }
    }

    CreateConVar("sm_speclaser_version", PLUGIN_VERSION, "NT Spectator Lasers plugin version.", FCVAR_DONTRECORD);

    g_hCvar_BeamOffset_X = CreateConVar("sm_speclaser_offset_x", "16", "Relative laser start position X offset.");
    g_hCvar_BeamOffset_Y = CreateConVar("sm_speclaser_offset_y", "-4.5", "Relative laser start position Y offset.");
    g_hCvar_BeamOffset_Z = CreateConVar("sm_speclaser_offset_z", "-1", "Relative laser start position Z offset.");

    g_hCvar_BeamWidth = CreateConVar("sm_speclaser_beam_width", "0.2", "Spectator laser beam width.");

    g_hCvar_BeamColor_R = CreateConVar("sm_speclaser_color_r", "33", "Spectator laser beam color, red channel. Note that this is affected by the texture base color, so it may not be the actual final RGB value.");
    g_hCvar_BeamColor_G = CreateConVar("sm_speclaser_color_g", "66", "Spectator laser beam color, green channel. Note that this is affected by the texture base color, so it may not be the actual final RGB value.");
    g_hCvar_BeamColor_B = CreateConVar("sm_speclaser_color_b", "66", "Spectator laser beam color, blue channel. Note that this is affected by the texture base color, so it may not be the actual final RGB value.");
    g_hCvar_BeamColor_A = CreateConVar("sm_speclaser_color_a", "223", "Spectator laser beam color, alpha channel.");

#if defined(INCLUDE_TRIG_LOOKUP_TABLES)
    g_hCvar_UseTrigLookup = CreateConVar("sm_speclaser_trig_lookup", "1", "Whether to use pre-calculated lookup tables for trigonometric calls.");
#endif

#if defined(DEBUG_PROFILE)
    g_hCvar_ProfileOutput = CreateConVar("sm_speclaser_profile_output", "0", "Whether to print plugin performance profiling info. This cvar should be compiled in only for debug.");
#endif
}

public void OnMapStart()
{
    if (!FileExists(BEAM_ASSET, true, NULL_STRING)) {
        SetFailState("Beam asset \"%s\" couldn't be found.", BEAM_ASSET);
    } else {
        _beamModel = PrecacheModel(BEAM_ASSET);
    }
}

public void OnClientConnected(int client)
{
    if (IsClientReplay(client) || IsClientSourceTV(client)) {
        AddPlayerToArray(spectators, num_spectating, client);
    }
}

public void OnClientDisconnect(int client)
{
    RemovePlayerFromArray(players, num_playing, client);
    RemovePlayerFromArray(spectators, num_spectating, client);
}

public void Event_PlayerDeath(Event event, const char[] name, bool dontBroadcast)
{
    int victim = GetClientOfUserId(event.GetInt("userid"));
    if (victim != 0) {
        RemovePlayerFromArray(players, num_playing, victim);
        RemovePlayerFromArray(spectators, num_spectating, victim);
    }
}

public void Event_PlayerSpawn(Event event, const char[] name, bool dontBroadcast)
{
    int client = GetClientOfUserId(event.GetInt("userid"));
    if (client != 0) {
        AddPlayerToArray(players, num_playing, client);
        RemovePlayerFromArray(spectators, num_spectating, client);
    }
}

public void Event_PlayerTeam(Event event, const char[] name, bool dontBroadcast)
{
    int client = GetClientOfUserId(event.GetInt("userid"));
    if (client == 0 || !IsClientConnected(client)) {
        return;
    }

    if (!event.GetBool("disconnect")) {
        int team = event.GetInt("team");
        if (team > NEO_TEAM_SPECTATOR) {
            AddPlayerToArray(players, num_playing, client);
            RemovePlayerFromArray(spectators, num_spectating, client);
        } else if ((!IsFakeClient(client)) && (team == NEO_TEAM_SPECTATOR)) {
            AddPlayerToArray(spectators, num_spectating, client);
            RemovePlayerFromArray(players, num_playing, client);
        }
    }
}

public void OnGameFrame()
{
#if defined(DEBUG_PROFILE)
    _prof.Start();
#endif

    if (num_spectating == 0) {
#if defined(DEBUG_PROFILE)
        _prof.Stop();
#endif
        return;
    }

    for (int i = 0; i < num_playing; ++i) {
        DrawLaser(players[i]);
    }

#if defined(DEBUG_PROFILE)
    _prof.Stop();
    // 10 seconds timeframe for a 66 tick server.
#define NUM_DEBUG_PROFILE_SAMPLES 660
    static float samples[NUM_DEBUG_PROFILE_SAMPLES];
    static int num_samples = 0;
    if (g_hCvar_ProfileOutput.BoolValue && num_samples == 0) {
#if !defined(INCLUDE_TRIG_LOOKUP_TABLES)
        PrintToDevs("Sampling for spec lasers ::OnGameFrame profile (trig. lookup tables disabled on compile)");
#else
        PrintToDevs("Sampling for spec lasers ::OnGameFrame profile (using trig. lookup tables: %s)",
            g_hCvar_UseTrigLookup.BoolValue ? "yes" : "no");
#endif
    }

    samples[num_samples++] = _prof.Time;
    if (num_samples == NUM_DEBUG_PROFILE_SAMPLES) {
        float average;
        for (int i = 0; i < num_samples; ++i) {
            average += samples[i];
        }
        average /= num_samples;
        num_samples = 0;
        if (g_hCvar_ProfileOutput.BoolValue) {
            PrintToDevs("Spec lasers ::OnGameFrame avg. latency over %d samples: %f",
                NUM_DEBUG_PROFILE_SAMPLES, average);
        }
    }
#endif
}

void GetSinCos(float value, float& sine, float& cosine)
{
#if defined(INCLUDE_TRIG_LOOKUP_TABLES)
    if (!g_hCvar_UseTrigLookup.BoolValue)
#endif
    {
        float a = value * PI_OVER_180;
        sine = Sine(a);
        cosine = Cosine(a);
        return;
    }

#if defined(INCLUDE_TRIG_LOOKUP_TABLES)
    int index = RoundToNearest(value * _truncate_helper);
    if (index < 0) {
        index += 360;
    } else if (index >= 360) {
        index -= 360;
    }

    sine = value < 0 ? -_sin_lookup_table[index] : _sin_lookup_table[index];
    cosine = _cos_lookup_table[index];

#if(0)
    PrintToServer("In: %f Sin Ret: %f vs %f",
        value,
        sine,
        Sine(value * PI_OVER_180));
#endif

#if(0)
    PrintToServer("In: %f Cos Ret: %f vs %f",
        value,
        cosine,
        Cosine(value * PI_OVER_180));
#endif
#endif
}

void DrawLaser(int client)
{
    float eye_pos[3], eye_ang[3], trace_end_pos[3];

    GetClientEyePosition(client, eye_pos);
    GetClientEyeAngles(client, eye_ang);

    TR_TraceRayFilter(eye_pos, eye_ang, ALL_VISIBLE_CONTENTS,
        RayType_Infinite, NotHitSelf, client);
    TR_GetEndPosition(trace_end_pos, INVALID_HANDLE);

    float sp, sy, sr, cp, cy, cr;
    GetSinCos(eye_ang[0], sp, cp);
    GetSinCos(eye_ang[1], sy, cy);
    GetSinCos(eye_ang[2], sr, cr);

    float crcy = cr * cy;
    float crsy = cr * sy;
    float srcy = sr * cy;
    float srsy = sr * sy;

    float matrix[3][3];
    matrix[0][0] = cp * cy;
    matrix[1][0] = cp * sy;
    matrix[2][0] = -sp;

    matrix[0][1] = sp * srcy - crsy;
    matrix[1][1] = sp * srsy + crcy;
    matrix[2][1] = sr * cp;

    matrix[0][2] = sp * crcy + srsy;
    matrix[1][2] = sp * crsy - srcy;
    matrix[2][2] = cr * cp;

    float offset[3];
    offset[0] = g_hCvar_BeamOffset_X.FloatValue;
    offset[1] = g_hCvar_BeamOffset_Y.FloatValue;
    offset[2] = g_hCvar_BeamOffset_Z.FloatValue;

    eye_pos[0] += GetVectorDotProduct(offset, matrix[0]);
    eye_pos[1] += GetVectorDotProduct(offset, matrix[1]);
    eye_pos[2] += GetVectorDotProduct(offset, matrix[2]);

    int color[4];
    color[0] = g_hCvar_BeamColor_R.IntValue;
    color[1] = g_hCvar_BeamColor_G.IntValue;
    color[2] = g_hCvar_BeamColor_B.IntValue;
    color[3] = g_hCvar_BeamColor_A.IntValue;

    TE_SetupBeamPoints(
        eye_pos,                      // Start position of the beam.
        trace_end_pos,                // End position of the beam.
        _beamModel,                   // Precached model index.
        _beamModel,                   // Precached model index.
        0,                            // Initial frame to render.
        0,                            // Beam frame rate.
        0.051,                        // Time duration of the beam (>0.05 seems to be the minimum)
        g_hCvar_BeamWidth.FloatValue, // Initial beam width.
        g_hCvar_BeamWidth.FloatValue, // Final beam width.
        0,                            // Beam fade time duration.
        1.0,                          // Beam amplitude.
        color,                        // Color array (r, g, b, a).
        0                             // Speed of the beam.
    );

    TE_Send(spectators, num_spectating, 0.0);
}

bool NotHitSelf(int hitEntity, int contentsMask, int selfEntity)
{
    return hitEntity != selfEntity;
}

void AddPlayerToArray(int[] array, int& num_elements, const int player)
{
    for (int i = 0; i < num_elements; ++i) {
        if (array[i] == player) {
            return;
        }
    }
    array[num_elements++] = player;
}

void RemovePlayerFromArray(int[] array, int& num_elements, const int player)
{
    for (int i = 0; i < num_elements; ++i) {
        if (array[i] == player) {
            for (int j = i + 1; j < num_elements; ++j) {
                array[j - 1] = array[j]; // move each superseding element back
            }
            // clear the trailing copy of the final moved element
            array[--num_elements] = 0;
            return;
        }
    }
}

#if defined(DEBUG_PROFILE)
void PrintToDevs(const char[] msg, any ...)
{
    decl String:formatMsg[512];
    VFormat(formatMsg, sizeof(formatMsg), msg, 2);

    for (int client = 1; client <= MaxClients; ++client) {
        if (IsClientConnected(client) && GetAdminFlag(GetUserAdmin(client), Admin_RCON)) {
            PrintToConsole(client, formatMsg);
        }
    }
}
#endif