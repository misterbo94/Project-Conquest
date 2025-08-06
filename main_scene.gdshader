shader_type canvas_item;

// --- Uniforms esistenti ---
uniform mat4 world_to_local_transform;
uniform vec2 grid_origin_offset;
uniform float tile_half_width;
uniform float tile_half_height;
uniform sampler2D control_texture : filter_nearest, repeat_disable;
uniform float progress;
uniform float anim_target_state;
uniform vec2 anim_mother_coords;
uniform vec2 map_size_in_tiles;

uniform float min_gradient_width : hint_range(0.0, 10.0, 0.5) = 2.0;

// --- Parametri per HSV ---
uniform float hue_shift : hint_range(0.0, 360.0, 1.0) = 220.0;
uniform float saturation : hint_range(0.0, 2.0, 0.05) = 1.0;
uniform float brightness : hint_range(0.0, 2.0, 0.05) = 1.0;

// --- Parametri per Border Gradient ---
uniform float gradient_width : hint_range(0.0, 20.0, 0.5) = 8.0;
uniform int dither_type = 1;
uniform float dither_scale : hint_range(1.0, 8.0, 0.5) = 3.0;
uniform float gradient_strength : hint_range(0.0, 1.0, 0.1) = 0.8;

// --- DEBUG CONTROLS ---
uniform bool debug_mode = false;
uniform int debug_view = 0; // 0=off, 1=border_distance, 2=pattern, 3=states, 4=final_decision

varying vec2 local_pos;

// Funzione per ottenere lo stato di una tile specifica
float get_tile_state(vec2 tile_coord) {
    
    // === FASE 1: CONTROLLO BOUNDS (LIMITI MAPPA) ===
    // Verifica se le coordinate sono dentro i limiti della mappa
    if (tile_coord.x < 0.0 || tile_coord.x >= map_size_in_tiles.x ||
        tile_coord.y < 0.0 || tile_coord.y >= map_size_in_tiles.y) {
        return -1.0;  // Fuori mappa = stato "invalido" (-1)
    }
    
    // === FASE 2: CONVERSIONE COORDINATE TILE → UV TEXTURE ===
    // tile_coord è in coordinate discrete (es. 5,3 = tile alla riga 5, colonna 3)
    // Dobbiamo convertire in coordinate UV (0.0-1.0) per leggere la texture
    
    // + vec2(0.5, -0.5): centra il sample nella tile
    //   0.5 in X = centrato orizzontalmente
    //  -0.5 in Y = compensa il fatto che le coordinate Y sono invertite tra tile e texture
    // / map_size_in_tiles: normalizza a 0.0-1.0
    vec2 uv = (tile_coord + vec2(0.5, -0.5)) / map_size_in_tiles;
    
    // === FASE 3: LETTURA DATI DALLA CONTROL TEXTURE ===
    // La texture contiene 4 canali (RGBA) con informazioni per ogni tile:
    // R = coordinata X della "tile madre" (chi controlla questa tile)  
    // G = coordinata Y della "tile madre"
    // B = stato base della tile (0.0=neutrale, 0.5=giocatore1, 1.0=giocatore2, etc.)
    // A = (non usato in questa funzione)
    vec4 data = texture(control_texture, uv);
    
    // === FASE 4: DECODIFICA COORDINATE "MADRE" ===
    // Le coordinate madre sono salvate normalizzate (0.0-1.0) nei canali R,G
    // Dobbiamo convertirle back in coordinate discrete
    float coord_scale = map_size_in_tiles.x - 1.0;  // Scale factor (es. mappa 10x10 → scale = 9)
    vec2 mother_coords = vec2(data.r, data.g) * coord_scale;  // Denormalizza a coordinate discrete
    
    // === FASE 5: CONTROLLO ANIMAZIONE IN CORSO ===
    // Se c'è un'animazione di conquista in corso, questa tile potrebbe essere coinvolta
    
    // floor(mother_coords + 0.5): arrotonda le coordinate madre alle coordinate discrete più vicine
    // distance(..., anim_mother_coords) < 0.1: verifica se questa tile appartiene alla regione che si sta animando
    if (distance(floor(mother_coords + 0.5), anim_mother_coords) < 0.1) {
        // Questa tile fa parte della regione in animazione!
        // Interpola tra stato vecchio (data.b) e stato nuovo (anim_target_state)
        // progress va da 0.0 (inizio animazione) a 1.0 (fine animazione)
        return mix(data.b, anim_target_state, progress);
    }
    
    // === FASE 6: RITORNA STATO NORMALE ===
    // Nessuna animazione in corso, ritorna lo stato base della tile
    return data.b;
}

// Calcola la distanza dal confine più vicino
float calculate_precise_border_distance(vec2 current_pos) {
    vec2 current_tile = floor(current_pos);
    float current_state = get_tile_state(current_tile);
    
    float min_distance = 999.0;
    
    // Calcola quante tile controllare in base a gradient_width
    int search_radius = int(ceil(gradient_width / tile_half_width)) + 1;
    
    // Cerca in un'area più ampia
    for (int x = -search_radius; x <= search_radius; x++) {
        for (int y = -search_radius; y <= search_radius; y++) {
            if (x == 0 && y == 0) continue;
            
            vec2 neighbor_tile = current_tile + vec2(float(x), float(y));
            float neighbor_state = get_tile_state(neighbor_tile);
            
            // Se il vicino ha uno stato diverso
            if (neighbor_state >= 0.0 && abs(neighbor_state - current_state) > 0.1) {
                // Calcola distanza PIXEL-PERFECT al confine di questa tile
                vec2 current_fract = fract(current_pos);
                vec2 direction = vec2(float(x), float(y));
                
                // Punto più vicino sul confine di questa tile neighbor
                vec2 border_point;
                if (abs(abs(direction.x) - 1.0) < 0.001 && abs(abs(direction.y)-1.0) < .001) {
                    // Confine diagonale (angolo)
                    border_point = current_tile + vec2(
                        direction.x > 0.0 ? 1.0 : 0.0,
                        direction.y > 0.0 ? 1.0 : 0.0
                    );
                } else if (abs(direction.x) > abs(direction.y)) {
                    // Confine verticale
                    border_point = vec2(
                        current_tile.x + (direction.x > 0.0 ? 1.0 : 0.0),
                        current_pos.y
                    );
                } else {
                    // Confine orizzontale
                    border_point = vec2(
                        current_pos.x,
                        current_tile.y + (direction.y > 0.0 ? 1.0 : 0.0)
                    );
                }
                
                float distance = length(current_pos - border_point);
                min_distance = min(min_distance, distance);
            }
        }
    }
    
    return min_distance;
}

// Trova lo stato del vicino più vicino
float find_nearest_neighbor_state(vec2 current_pos) {
    vec2 current_tile = floor(current_pos);
    float current_state = get_tile_state(current_tile);
    
    for (int x = -1; x <= 1; x++) {
        for (int y = -1; y <= 1; y++) {
            if (x == 0 && y == 0) continue;
            
            vec2 neighbor_tile = current_tile + vec2(float(x), float(y));
            float neighbor_state = get_tile_state(neighbor_tile);
            
            if (neighbor_state >= 0.0 && abs(neighbor_state - current_state) > 0.1) {
                return neighbor_state;
            }
        }
    }
    
    return -1.0;
}

// decide il pattern
float get_pattern(vec2 pos, float distance_to_border, float current_state, float neighbor_state) {
    if (dither_type == 1) {
        // === CALCOLO POSIZIONE NELLA GRIGLIA ===
        vec2 grid_pos = floor(pos * dither_scale);
        vec2 grid_fract = fract(pos * dither_scale);
        vec2 center = abs(grid_fract - 0.5);
        
        // === PATTERN CHECKER FISSO ===
        // Somma coordinate pari = nero (0.0), dispari = bianco (1.0)
        float checker = mod(grid_pos.x + grid_pos.y, 2.0);
        
        // === LOGICA DELLA TABELLA ===
        // Determina quale stato dovrebbe avere dots in questa posizione
        float target_dots_state;
        
        if (checker < 0.5) {
            // NERO: dots del Giocatore 1 (stato 0.0)
            target_dots_state = 0.0;
        } else {
            // BIANCO: dots del Giocatore 2 (stato 1.0)  
            target_dots_state = 1.0;
        }
        
        // === APPLICAZIONE TABELLA LOGICA ===
        // Verifica se uno dei due stati corrisponde al target per questa casella
        bool current_gets_dots = abs(current_state - target_dots_state) < 0.1;
        bool neighbor_gets_dots = abs(neighbor_state - target_dots_state) < 0.1;
        
        // Se nessuno dei due stati corrisponde al target (es. confine neutro-neutro)
        // usiamo il valore di default (favorisci current)
        if (!current_gets_dots && !neighbor_gets_dots) {
            current_gets_dots = true;
        }
        
        // === CALCOLO DIMENSIONE DOTS ===
        float distance_factor = clamp(distance_to_border / gradient_width, 0.0, 1.0);
        
        float dot_size;
        if (current_gets_dots) {
            // La regione corrente dovrebbe avere dots grandi qui
            // Make the variation much more extreme for testing
            dot_size = 0.01 + 0.48 * distance_factor;  // Da piccolissimi (0.01) a grandi (0.49)
        } else {
            // La regione corrente dovrebbe avere dots piccoli (valleys grandi)
            // Make the variation much more extreme for testing
            dot_size = 0.49 - 0.48 * distance_factor;  // Da grandi (0.49) a piccolissimi (0.01)
        }
        
        dot_size = clamp(dot_size, 0.01, 0.49);
        
        // === RENDERING FINALE ===
        bool show_dot = step(length(center), dot_size) > 0.5;
        
        if (current_gets_dots) {
            return show_dot ? 1.0 : 0.0;  // Dots = corrente, valleys = vicino
        } else {
            return show_dot ? 0.0 : 1.0;  // Dots = vicino, valleys = corrente  
        }
    }
    
    // Fallback per noise pattern
    vec2 noise_coord = floor(pos * dither_scale);
    float noise = fract(sin(dot(noise_coord, vec2(12.9898, 78.233))) * 43758.5453);
    return step(0.5, noise);
}


// Funzione HSV
vec3 apply_hue_shift(vec3 original_rgb, float state) {
    if (state < 0.01) { return original_rgb; }
    float v = brightness;
    float s = saturation;
    float hue = hue_shift * state;
    float vsu = v * s * cos(hue * PI / 180.0);
    float vsw = v * s * sin(hue * PI / 180.0);
    vec3 result;
    result.r = (.299*v + .701*vsu + .168*vsw) * original_rgb.r + (.587*v - .587*vsu + .330*vsw) * original_rgb.g + (.114*v - .114*vsu - .497*vsw) * original_rgb.b;
    result.g = (.299*v - .299*vsu - .328*vsw) * original_rgb.r + (.587*v + .413*vsu + .035*vsw) * original_rgb.g + (.114*v - .114*vsu + .292*vsw) * original_rgb.b;
    result.b = (.299*v - .300*vsu + 1.25*vsw) * original_rgb.r + (.587*v - .588*vsu - 1.05*vsw) * original_rgb.g + (.114*v + .886*vsu - .203*vsw) * original_rgb.b;
    return result;
}

void vertex() {
    vec2 world_pos = (MODEL_MATRIX * vec4(VERTEX, 0.0, 1.0)).xy;
    vec2 local_pos_raw = (world_to_local_transform * vec4(world_pos, 0.0, 1.0)).xy;
    local_pos = local_pos_raw - grid_origin_offset;
}

void fragment() {
    // Converti in coordinate tile
    vec2 map_coords;
    map_coords.x = (local_pos.x / tile_half_width - local_pos.y / tile_half_height) / 2.0;
    map_coords.y = (local_pos.x / tile_half_width + local_pos.y / tile_half_height) / 2.0;
    
    vec2 tile_pos = map_coords + vec2(1.0, 1.0);
    vec2 current_tile = floor(tile_pos);
    
    // Stato base della tile corrente
    float current_state = get_tile_state(current_tile);
    float final_state = current_state;
    
    // --- DEBUG VISUALIZATIONS (priorità massima) ---
    if (debug_mode && debug_view > 0) {
        if (debug_view == 1) {
            // Visualizza distanza dal confine (rosso = vicino, verde = lontano)
            float border_distance = calculate_precise_border_distance(tile_pos);
            float normalized_distance = clamp(border_distance / gradient_width, 0.0, 1.0);
            COLOR = vec4(1.0 - normalized_distance, normalized_distance, 0.0, 1.0);
        } else if (debug_view == 2) {
            // Visualizza il pattern (bianco = pattern on, nero = pattern off)
            float border_distance = calculate_precise_border_distance(tile_pos);
            if (border_distance < gradient_width) {
                //float pattern = get_pattern(tile_pos, border_distance);
                //COLOR = vec4(vec3(pattern), 1.0);
				COLOR = vec4(1.0, 0.0, 0.0, 1.0); // Rosso
            } else {
                COLOR = vec4(0.5, 0.5, 0.5, 1.0); // Grigio = fuori dal gradiente
            }
        } else if (debug_view == 3) {
            // Visualizza gli stati (diversi colori per ogni stato)
            if (current_state == 0.0) COLOR = vec4(1.0, 0.0, 0.0, 1.0); // Rosso
            else if (current_state == 0.5) COLOR = vec4(0.0, 1.0, 0.0, 1.0); // Verde
            else if (current_state == 1.0) COLOR = vec4(0.0, 0.0, 1.0, 1.0); // Blu
            else COLOR = vec4(1.0, 1.0, 1.0, 1.0); // Bianco = stato sconosciuto
        } else if (debug_view == 4) {
            // Visualizza la decisione finale del gradiente
            float border_distance = calculate_precise_border_distance(tile_pos);
            if (border_distance < gradient_width && gradient_width > 0.0) {
                float neighbor_state = find_nearest_neighbor_state(tile_pos);
                if (neighbor_state >= 0.0) {
                    //float pattern = get_pattern(tile_pos, border_distance);
					COLOR = vec4(1.0, 0.0, 0.0, 1.0); // Rosso

                    //if (pattern > 0.5) {
                        //COLOR = vec4(1.0, 1.0, 0.0, 1.0); // Giallo = colore corrente
                    //} else {
                        //COLOR = vec4(1.0, 0.0, 1.0, 1.0); // Magenta = colore vicino
                    //}
                } else {
                    COLOR = vec4(0.0, 1.0, 1.0, 1.0); // Ciano = nessun vicino diverso
                }
            } else {
                COLOR = vec4(0.5, 0.5, 0.5, 1.0); // Grigio = fuori gradiente
            }
        } else if (debug_view == 5) {
            // Debug: Visualizza dot_size calculation
            float border_distance = calculate_precise_border_distance(tile_pos);
            if (border_distance < gradient_width && gradient_width > 0.0) {
                float neighbor_state = find_nearest_neighbor_state(tile_pos);
                if (neighbor_state >= 0.0) {
                    // Simulate the pattern calculation to get dot_size
                    vec2 current_tile = floor(tile_pos);
                    float current_state = get_tile_state(current_tile);
                    
                    vec2 grid_pos = floor(tile_pos * dither_scale);
                    float checker = mod(grid_pos.x + grid_pos.y, 2.0);
                    
                    float target_dots_state = checker < 0.5 ? 0.0 : 1.0;
                    bool current_gets_dots = abs(current_state - target_dots_state) < 0.1;
                    
                    float distance_factor = clamp(border_distance / gradient_width, 0.0, 1.0);
                    
                    float dot_size;
                    if (current_gets_dots) {
                        // Match the extreme values from get_pattern function
                        dot_size = 0.01 + 0.48 * distance_factor;
                    } else {
                        dot_size = 0.49 - 0.48 * distance_factor;
                    }
                    
                    // Visualize dot_size as color intensity (0.0=black, 0.5=gray, 1.0=white)
                    float normalized_dot_size = dot_size; // Already in 0-1 range roughly
                    COLOR = vec4(normalized_dot_size, normalized_dot_size, normalized_dot_size, 1.0);
                } else {
                    COLOR = vec4(0.0, 1.0, 1.0, 1.0); // Ciano = nessun vicino diverso
                }
            } else {
                COLOR = vec4(0.5, 0.5, 0.5, 1.0); // Grigio = fuori gradiente
            }
        } else if (debug_view == 6) {
            // Debug: Visualizza actual pattern output
            float border_distance = calculate_precise_border_distance(tile_pos);
            if (border_distance < gradient_width && gradient_width > 0.0) {
                float neighbor_state = find_nearest_neighbor_state(tile_pos);
                if (neighbor_state >= 0.0) {
                    float current_state = get_tile_state(floor(tile_pos));
                    float pattern = get_pattern(tile_pos, border_distance, current_state, neighbor_state);
                    COLOR = vec4(vec3(pattern), 1.0); // Black and white pattern
                } else {
                    COLOR = vec4(0.0, 1.0, 1.0, 1.0); // Ciano = nessun vicino diverso
                }
            } else {
                COLOR = vec4(0.5, 0.5, 0.5, 1.0); // Grigio = fuori gradiente
            }
        }
    } else {
        // --- LOGICA NORMALE (debug_mode = false O debug_view = 0) ---
        
        // === CONTROLLO SE IL GRADIENTE È ATTIVO ===
        if (gradient_width > 0.0) {
            
            // === FASE 1: CALCOLA DISTANZA DAL CONFINE ===
            // Usa la funzione avanzata che cerca confini in un raggio più ampio
            float border_distance = calculate_precise_border_distance(tile_pos);
            
            // === FASE 2: VERIFICA SE SIAMO NELLA ZONA GRADIENTE ===
            // Solo i pixel entro gradient_width dal confine partecipano al gradiente
            if (border_distance < gradient_width) {
                
                // === FASE 3: PREPARAZIONE PER LA RICERCA DEL VICINO ===
                vec2 current_tile = floor(tile_pos);           // Tile corrente (coordinate discrete)
                float current_state = get_tile_state(current_tile);  // Stato della tile corrente
                float closest_neighbor_state = -1.0;          // Stato del vicino più vicino (default: non trovato)
                
                // Calcola raggio di ricerca basato sui parametri
                // max(gradient_width, min_gradient_width) = usa il valore più grande
                // Diviso per tile_half_width = converti da pixel a "unità tile"
                // ceil() = arrotonda per eccesso per essere sicuri
                // max(1, ...) = minimo 1 tile di raggio
                int search_radius = max(1, int(ceil(max(gradient_width, min_gradient_width) / tile_half_width)));
                
                // === FASE 4: CERCA IL PRIMO VICINO CON STATO DIVERSO ===
                // Loop annidato per controllare area quadrata centrata sulla tile corrente
                for (int x = -search_radius; x <= search_radius; x++) {
                    for (int y = -search_radius; y <= search_radius; y++) {
                        if (x == 0 && y == 0) continue;  // Salta la tile corrente
                        
                        // Calcola coordinate del vicino da testare
                        vec2 neighbor_tile = current_tile + vec2(float(x), float(y));
                        float test_state = get_tile_state(neighbor_tile);  // Leggi stato del vicino
                        
                        // === VERIFICA SE È UN CONFINE VALIDO ===
                        // test_state >= 0.0: il vicino esiste (non fuori mappa)
                        // abs(test_state - current_state) > 0.1: ha stato diverso (soglia 0.1 per tolleranza float)
                        if (test_state >= 0.0 && abs(test_state - current_state) > 0.1) {
                            closest_neighbor_state = test_state;  // Trovato! Salva lo stato
                            break; // Esci dal loop interno (primo trovato = più vicino)
                        }
                    }
                    // Se hai trovato un vicino, esci anche dal loop esterno
                    if (closest_neighbor_state >= 0.0) break;
                }
                
                // === FASE 5: APPLICA IL PATTERN SE TROVATO UN CONFINE ===
                if (closest_neighbor_state >= 0.0) {
                    // Chiama la funzione pattern che decide quale colore usare
                    // Parametri: posizione, distanza dal confine, stato corrente, stato vicino
                    float pattern = get_pattern(tile_pos, border_distance, current_state, closest_neighbor_state);
                    
                    // === DECISIONE FINALE DEL COLORE ===
                    if (pattern > 0.5) {
                        final_state = current_state;      // Usa il colore della regione corrente
                    } else {
                        final_state = closest_neighbor_state;  // Usa il colore della regione vicina
                    }
                }
                // Se closest_neighbor_state < 0.0: nessun confine trovato, mantieni final_state = current_state
            }
            // Se border_distance >= gradient_width: troppo lontano dal confine, mantieni final_state = current_state
        }
        // Se gradient_width <= 0.0: gradiente disabilitato, mantieni final_state = current_state
        
        // Applica il colore finale
        vec4 original_color = texture(TEXTURE, UV);
        vec3 final_rgb = apply_hue_shift(original_color.rgb, final_state);
        COLOR = vec4(final_rgb, original_color.a);
    }
}