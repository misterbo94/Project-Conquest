shader_type canvas_item;

// === TEXTURE ESSENZIALI ===
uniform sampler2D control_texture : filter_nearest, repeat_disable;     
uniform sampler2D animation_texture : filter_nearest, repeat_disable;   

// === UNIFORMS GEOMETRIA ===
uniform mat4 world_to_local_transform;
uniform vec2 grid_origin_offset;
uniform float tile_half_width;
uniform float tile_half_height;
uniform vec2 map_size_in_tiles;

// === PARAMETRI PATTERN ===
uniform float dither_scale : hint_range(1.0, 8.0, 0.05) = 3.0;
uniform float max_dot_size : hint_range(0.1, 1.0, 0.05) = 0.65;

// === PARAMETRI HSV ===
uniform float hue_shift : hint_range(0.0, 360.0, 1.0) = 220.0;
uniform float saturation : hint_range(0.0, 2.0, 0.05) = 1.0;
uniform float brightness : hint_range(0.0, 2.0, 0.05) = 1.0;

// === DEBUG ===
uniform bool debug_mode = false;
uniform int debug_view = 0; 

varying vec2 local_pos;

// === STRUTTURE DATI ===
struct TileData {
    vec2 mother_coord;
    float region_state;
    float aura_strength;
};

struct AnimationData {
    float progress;
    float from_state;
    float to_state;
    float distance_to_mother;
};

// === ✅ FUNZIONI LETTURA TEXTURE - COMPLETE ===
TileData get_tile_data(vec2 tile_coord) {
    TileData data;
    
    // Verifica bounds
    if (tile_coord.x < 0.0 || tile_coord.x >= map_size_in_tiles.x ||
        tile_coord.y < 0.0 || tile_coord.y >= map_size_in_tiles.y) {
        data.mother_coord = vec2(-1.0, -1.0);
        data.region_state = -1.0;  // Invalido
        data.aura_strength = 0.0;
        return data;
    }
    
    // Converti a UV
    vec2 uv = (tile_coord + vec2(0.5, -0.5)) / map_size_in_tiles;
    
    // Leggi da control_texture
    vec4 control_data = texture(control_texture, uv);
    
    // Decodifica coordinate madre
    float coord_scale = map_size_in_tiles.x - 1.0;
    data.mother_coord = vec2(control_data.r, control_data.g) * coord_scale;
    data.region_state = control_data.b;  // Stato puro
    data.aura_strength = control_data.a;
    
    return data;
}

AnimationData get_animation_data(vec2 tile_coord) {
    AnimationData data;
    
    // Verifica bounds
    if (tile_coord.x < 0.0 || tile_coord.x >= map_size_in_tiles.x ||
        tile_coord.y < 0.0 || tile_coord.y >= map_size_in_tiles.y) {
        data.progress = 0.0;
        data.from_state = 0.5;
        data.to_state = 0.5;
        data.distance_to_mother = 999.0;
        return data;
    }
    
    // Converti a UV
    vec2 uv = (tile_coord + vec2(0.5, -0.5)) / map_size_in_tiles;
    
    // Leggi da animation_texture
    vec4 anim_data = texture(animation_texture, uv);
    
    data.progress = anim_data.r;
    data.from_state = anim_data.g;
    data.to_state = anim_data.b;
    data.distance_to_mother = anim_data.a;
    
    return data;
}

// === PATTERN SCACCHIERA ===
bool is_player1_tile(vec2 pos) {
    vec2 grid_pos = floor(pos * dither_scale);
    return mod(grid_pos.x + grid_pos.y, 2.0) < 0.5;
}

// === PATTERN DOT SEMPLIFICATO ===
float get_dot_pattern(vec2 pos, AnimationData anim_data) {
    if (anim_data.progress < 0.001) {
        return 1.0; // Nessuna animazione
    }
    
    // Determina stati
    float current_state = anim_data.from_state;
    float target_state = anim_data.to_state;
    
    bool current_is_player1 = current_state < 0.4;
    bool current_is_player2 = current_state > 0.6;
    bool current_is_neutral = !current_is_player1 && !current_is_player2;
    
    bool target_is_player1 = target_state < 0.4;
    bool target_is_player2 = target_state > 0.6;
    bool target_is_neutral = !target_is_player1 && !target_is_player2;
    
    // ✅ TRICK NEUTRO SEMPLIFICATO
    if (current_is_neutral && target_is_player1) {
        current_is_player2 = true;
        current_is_neutral = false;
    }
    if (current_is_neutral && target_is_player2) {
        current_is_player1 = true;
        current_is_neutral = false;
    }
    if (current_is_player1 && target_is_neutral) {
        target_is_player2 = true;
        target_is_neutral = false;
    }
    if (current_is_player2 && target_is_neutral) {
        target_is_player1 = true;
        target_is_neutral = false;
    }
    
    // Scacchiera
    bool p1_commands = is_player1_tile(pos);
    
    // Calcolo dot
    vec2 grid_fract = fract(pos * dither_scale);
    vec2 center_offset = abs(grid_fract - 0.5);
    float center_dist = length(center_offset);
    
    // ✅ DIMENSIONE DOT BASATA SU PROGRESSO E CONTROLLO
    float dot_size;
    
    if (p1_commands) {
        if (target_is_player1) {
            dot_size = max_dot_size * anim_data.progress; // P1 conquista: cresce
        } else {
            dot_size = max_dot_size * (1.0 - anim_data.progress); // P1 perde: diminuisce
        }
    } else {
        if (target_is_player2) {
            dot_size = max_dot_size * anim_data.progress; // P2 conquista: cresce
        } else {
            dot_size = max_dot_size * (1.0 - anim_data.progress); // P2 perde: diminuisce
        }
    }
    
    bool inside_dot = center_dist < dot_size;
    
    // ✅ COLORE FINALE
    if (p1_commands) {
        if (target_is_player1) {
            return inside_dot ? target_state : current_state;
        } else {
            return inside_dot ? current_state : target_state;
        }
    } else {
        if (target_is_player2) {
            return inside_dot ? target_state : current_state;
        } else {
            return inside_dot ? current_state : target_state;
        }
    }
}

// === HSV ===
vec3 apply_hue_shift(vec3 original_rgb, float state) {
    if (abs(state - 0.5) < 0.1) {
        return original_rgb; // Neutrale
    }
    
    if (state < -0.5) {
        return original_rgb; // Invalido
    }
    
    float hue_degrees;
    if (state <= 0.5) {
        hue_degrees = 240.0; // Blu per P1
    } else {
        hue_degrees = 120.0; // Verde per P2  
    }
    
    float intensity = abs(state - 0.5) * 2.0;
    intensity = clamp(intensity, 0.0, 1.0);
    
    float v = brightness * (0.5 + 0.5 * intensity);
    float s = saturation * intensity;
    float hue_rad = hue_degrees * PI / 180.0;
    
    float vsu = v * s * cos(hue_rad);
    float vsw = v * s * sin(hue_rad);
    
    vec3 result;
    result.r = (.299*v + .701*vsu + .168*vsw) * original_rgb.r + (.587*v - .587*vsu + .330*vsw) * original_rgb.g + (.114*v - .114*vsu - .497*vsw) * original_rgb.b;
    result.g = (.299*v - .299*vsu - .328*vsw) * original_rgb.r + (.587*v + .413*vsu + .035*vsw) * original_rgb.g + (.114*v - .114*vsu + .292*vsw) * original_rgb.b;
    result.b = (.299*v - .300*vsu + 1.25*vsw) * original_rgb.r + (.587*v - .588*vsu - 1.05*vsw) * original_rgb.g + (.114*v + .886*vsu - .203*vsw) * original_rgb.b;
    
    return mix(original_rgb, result, intensity);
}

void vertex() {
    vec2 world_pos = (MODEL_MATRIX * vec4(VERTEX, 0.0, 1.0)).xy;
    vec2 local_pos_raw = (world_to_local_transform * vec4(world_pos, 0.0, 1.0)).xy;
    local_pos = local_pos_raw - grid_origin_offset;
}

void fragment() {
    // === CONVERSIONE COORDINATE ===
    vec2 map_coords;
    map_coords.x = (local_pos.x / tile_half_width - local_pos.y / tile_half_height) / 2.0;
    map_coords.y = (local_pos.x / tile_half_width + local_pos.y / tile_half_height) / 2.0;
    
    vec2 tile_pos = map_coords + vec2(1.0, 1.0);
    vec2 current_tile = floor(tile_pos);
    
    // === ✅ LETTURA DATI - FUNZIONI IMPLEMENTATE ===
    TileData tile_data = get_tile_data(current_tile);
    AnimationData anim_data = get_animation_data(current_tile);
    
    // === DEBUG SEMPLIFICATO ===
    if (debug_mode && debug_view > 0) {
        if (debug_view == 1) {
            // Debug: Stati control texture
            COLOR = vec4(tile_data.region_state, tile_data.region_state, tile_data.region_state, 1.0);
        } else if (debug_view == 2) {
            // Debug: Progresso animazione
            COLOR = vec4(anim_data.progress, 0.0, 0.0, 1.0);
        } else if (debug_view == 3) {
            // Debug: Scacchiera
            if (is_player1_tile(tile_pos)) {
                COLOR = vec4(1.0, 0.0, 0.0, 1.0); // Rosso = P1 tiles
            } else {
                COLOR = vec4(0.0, 0.0, 1.0, 1.0); // Blu = P2 tiles
            }
        } else if (debug_view == 4) {
            // Debug: Distance to mother
            float norm_distance = anim_data.distance_to_mother / 20.0;
            COLOR = vec4(norm_distance, norm_distance, norm_distance, 1.0);
        } else if (debug_view == 5) {
            // Debug: Pattern finale
            float pattern_state = get_dot_pattern(tile_pos, anim_data);
            COLOR = vec4(pattern_state, pattern_state, pattern_state, 1.0);
        }
    }
    
    // === LOGICA PRINCIPALE ===
    float final_state;
    
    // Se c'è animazione attiva, usa il pattern
    if (anim_data.progress > 0.001) {
        final_state = get_dot_pattern(tile_pos, anim_data);
    } else {
        // Usa stato base della tile
        final_state = tile_data.region_state;
    }
    
    // === APPLICAZIONE COLORE ===
    vec4 original_color = texture(TEXTURE, UV);
    vec3 final_rgb = apply_hue_shift(original_color.rgb, final_state);
    
    // Aggiungi effetto aura se presente
    if (tile_data.aura_strength > 0.1) {
        final_rgb = mix(final_rgb, vec3(1.0, 1.0, 0.0), tile_data.aura_strength * 0.3);
    }
    
    COLOR = vec4(final_rgb, original_color.a);
}