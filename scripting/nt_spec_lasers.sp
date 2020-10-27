#pragma semicolon 1

#include <sourcemod>
#include <sdktools>
#include <neotokyo>

#define PLUGIN_VERSION "0.1"

// The laser texture to use.
#define BEAM_ASSET "materials/sprites/purplelaser1.vmt"

#define NEO_MAX_PLAYERS 32
#define NEO_TEAM_SPECTATOR 1

static bool _is_playing[NEO_MAX_PLAYERS + 1];
static bool _is_spectating[NEO_MAX_PLAYERS + 1];

static int _beamModel;

ConVar g_hCvar_BeamOffset_X = null, g_hCvar_BeamOffset_Y = null, g_hCvar_BeamOffset_Z = null;
ConVar g_hCvar_BeamWidth = null;
ConVar g_hCvar_BeamColor_R = null, g_hCvar_BeamColor_G = null, g_hCvar_BeamColor_B = null, g_hCvar_BeamColor_A = null;

public Plugin myinfo = {
    name = "NT Spectator Lasers",
    description = "Draw laser lines for spectators to visualize which direction each player is aiming towards.",
    author = "Rain",
    version = PLUGIN_VERSION,
    url = "https://github.com/Rainyan/sourcemod-nt-spectator-lasers"
};

public void OnPluginStart()
{
    HookEvent("player_team", Event_PlayerTeam);

    for (int client = 1; client <= MaxClients; ++client) {
        if (IsClientConnected(client)) {
            int team = GetClientTeam(client);
            _is_spectating[client] = (team == NEO_TEAM_SPECTATOR);
            // Could also be unassigned team, which is < TEAM_SPECTATOR.
            // Both Jinrai and NSF are > TEAM_SPECTATOR.
            _is_playing[client] = (team > NEO_TEAM_SPECTATOR);
        }
    }

    CreateConVar("sm_speclaser_version", PLUGIN_VERSION, "NT Spectator Lasers plugin version.", FCVAR_DONTRECORD);

    g_hCvar_BeamOffset_X = CreateConVar("sm_speclaser_offset_x", "10", "Relative laser start position X offset.");
    g_hCvar_BeamOffset_Y = CreateConVar("sm_speclaser_offset_y", "-4.5", "Relative laser start position Y offset.");
    g_hCvar_BeamOffset_Z = CreateConVar("sm_speclaser_offset_z", "-1", "Relative laser start position Z offset.");

    g_hCvar_BeamWidth = CreateConVar("sm_speclaser_beam_width", "0.1", "Spectator laser beam width.");

    g_hCvar_BeamColor_R = CreateConVar("sm_speclaser_color_r", "33", "Spectator laser beam color, red channel. Note that this is affected by the texture base color, so it may not be the actual final RGB value.");
    g_hCvar_BeamColor_G = CreateConVar("sm_speclaser_color_g", "66", "Spectator laser beam color, green channel. Note that this is affected by the texture base color, so it may not be the actual final RGB value.");
    g_hCvar_BeamColor_B = CreateConVar("sm_speclaser_color_b", "66", "Spectator laser beam color, blue channel. Note that this is affected by the texture base color, so it may not be the actual final RGB value.");
    g_hCvar_BeamColor_A = CreateConVar("sm_speclaser_color_a", "223", "Spectator laser beam color, alpha channel.");
}

public void OnMapStart()
{
    if (!FileExists(BEAM_ASSET, true, NULL_STRING)) {
        SetFailState("Beam asset \"%s\" couldn't be found.", BEAM_ASSET);
    } else {
        _beamModel = PrecacheModel(BEAM_ASSET);
    }
}

public void OnClientDisconnect(int client)
{
    _is_playing[client] = false;
    _is_spectating[client] = false;
}

public void OnGameFrame()
{
    int spectators[NEO_MAX_PLAYERS], players[NEO_MAX_PLAYERS];
    int num_spectating = 0, num_playing = 0;

    for (int client = 1; client <= MaxClients; ++client) {
        if (_is_spectating[client]) {
            spectators[num_spectating++] = client;
        } else if (_is_playing[client]) {
            players[num_playing++] = client;
        }
    }

    if (num_spectating == 0 || num_playing == 0) {
        return;
    }

    for (int i = 0; i < num_playing; ++i) {
        DrawLaser(players[i]);
        TE_Send(spectators, num_spectating, 0.0);
    }
}

static float eye_pos[3], eye_ang[3], trace_end_pos[3];
void DrawLaser(int client)
{
    GetClientEyePosition(client, eye_pos);
    GetClientEyeAngles(client, eye_ang);

    TR_TraceRayFilter(eye_pos, eye_ang, ALL_VISIBLE_CONTENTS,
        RayType_Infinite, NotHitSelf, client);
    TR_GetEndPosition(trace_end_pos, INVALID_HANDLE);

#if !defined(PI)
#define PI 3.14159265359
// SourcePawn Compiler 1.10 won't optimise this constant division,
// so pre-calculating it.
#define PI_OVER_180 0.01745329252
#endif
    float sp = Sine(eye_ang[0] * PI_OVER_180);
    float sy = Sine(eye_ang[1] * PI_OVER_180);
    float sr = Sine(eye_ang[2] * PI_OVER_180);
    float cp = Cosine(eye_ang[0] * PI_OVER_180);
    float cy = Cosine(eye_ang[1] * PI_OVER_180);
    float cr = Cosine(eye_ang[2] * PI_OVER_180);

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
}

bool NotHitSelf(int hitEntity, int contentsMask, int selfEntity)
{
    return hitEntity != selfEntity;
}

public void Event_PlayerTeam(Event event, const char[] name, bool dontBroadcast)
{
    int client = GetClientOfUserId(event.GetInt("userid"));
    if (client == 0) {
        return;
    }

    if (!event.GetBool("disconnect")) {
        int team = event.GetInt("team");
        _is_spectating[client] = (team == NEO_TEAM_SPECTATOR);
        // Could also be unassigned team, which is < TEAM_SPECTATOR.
        // Both Jinrai and NSF are > TEAM_SPECTATOR.
        _is_playing[client] = (team > NEO_TEAM_SPECTATOR);
    }
}