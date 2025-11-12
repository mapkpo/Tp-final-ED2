import pygame
import sys
import math
from collections import deque

# intentar importar pyserial; si no está, cae a modo simulador
try:
    import serial
    HAS_SERIAL = True
except Exception:
    serial = None
    HAS_SERIAL = False

# Configuración serial (ajustar puerto)
SERIAL_PORT = "COM3"
BAUDRATE = 19200
SER_TIMEOUT = 0.01

# Configuración gráfica
WIDTH, HEIGHT = 1000, 600
FPS = 60

PLOT_MARGIN_X = 40
PLOT_TOP_MARGIN = 40
BOTTOM_RESERVED = 220  # espacio bajo la grafica para controles
BTN_H = 36
BTN_START_X = 40
STOP_BTN_WIDTH = 90
STOP_BTN_EXTRA_GAP = 40
WINDOW_MIN_WIDTH = 600
WINDOW_MIN_HEIGHT = 420

SLIDER_HEIGHT = 12
SLIDER_MIN_WIDTH = 220
SLIDER_MAX_WIDTH = 520

TIME_WINDOW_MIN = 0.001  # 1 ms
TIME_WINDOW_MAX = 60.0   # 60 s
DEFAULT_TIME_WINDOW = 0.1

BASE_SAMPLE_RATE = 1000.0  # muestras por segundo de referencia
RAW_BUFFER_PAD = 1000
# Simulación si no hay serial
SIM_FREQ = 5.0
SIM_AMP = 1.0
_sim_t = 0.0

# referencia de tensión del ADC (ajustar según hardware: 5.0, 3.3, etc.)
VREF = 5.0

def bin8_to_dec3(val):
    tmp = int(val) & 0xFF
    num2 = 0
    num1 = 0
    num0 = 0
    while tmp >= 100:
        tmp -= 100
        num2 += 1
    while tmp >= 10:
        tmp -= 10
        num1 += 1
    num0 = tmp
    return num2, num1, num0

def open_serial(port, baud):
    try:
        ser = serial.Serial(port, baud, timeout=SER_TIMEOUT)
        return ser
    except Exception as e:
        print("No se pudo abrir puerto serial:", e)
        return None

def draw_scope_grid(surface, rect, cols=10, rows=8, minor_steps=5, color_major=(60,60,60), color_minor=(40,40,40)):
    # fondo
    pygame.draw.rect(surface, (10,10,20), rect)
    # líneas menores
    for c in range(cols * minor_steps + 1):
        x = rect.left + c * (rect.width / (cols * minor_steps))
        color = color_minor
        pygame.draw.line(surface, color, (x, rect.top), (x, rect.bottom), 1)
    for r in range(rows * minor_steps + 1):
        y = rect.top + r * (rect.height / (rows * minor_steps))
        color = color_minor
        pygame.draw.line(surface, color, (rect.left, y), (rect.right, y), 1)
    # líneas mayores
    for c in range(cols + 1):
        x = rect.left + c * (rect.width / cols)
        pygame.draw.line(surface, color_major, (x, rect.top), (x, rect.bottom), 2)
    for r in range(rows + 1):
        y = rect.top + r * (rect.height / rows)
        pygame.draw.line(surface, color_major, (rect.left, y), (rect.right, y), 2)
    # ejes centrales
    pygame.draw.line(surface, (80,80,140), (rect.left, rect.centery), (rect.right, rect.centery), 2)
    pygame.draw.line(surface, (80,80,140), (rect.centerx, rect.top), (rect.centerx, rect.bottom), 2)

def draw_trace(surface, rect, buffer, color=(0,255,0)):
    if len(buffer) < 2:
        return
    pts = []
    for i, v in enumerate(buffer):
        x = rect.left + i
        y = rect.bottom - int((v / 255.0) * rect.height)
        pts.append((x, y))
    if len(pts) > 1:
        pygame.draw.lines(surface, color, False, pts, 2)

def draw_button(surface, rect, label, active=False):
    color_bg = (200,200,60) if active else (60,60,60)
    color_text = (10,10,10) if active else (220,220,220)
    pygame.draw.rect(surface, color_bg, rect, border_radius=6)
    pygame.draw.rect(surface, (0,0,0), rect, 2, border_radius=6)
    font = pygame.font.SysFont('Consolas', 18)
    text = font.render(label, True, color_text)
    tx = rect.left + (rect.width - text.get_width())//2
    ty = rect.top + (rect.height - text.get_height())//2
    surface.blit(text, (tx, ty))

def generate_sim_sample(t, freq=SIM_FREQ, amp=SIM_AMP):
    return amp * math.sin(2 * math.pi * freq * t)

def compute_layout(width, height):
    usable_width = max(200, width - 2 * PLOT_MARGIN_X)
    usable_height = max(200, height - (PLOT_TOP_MARGIN + BOTTOM_RESERVED))
    plot_rect = pygame.Rect(PLOT_MARGIN_X, PLOT_TOP_MARGIN, usable_width, usable_height)

    slider_width = max(SLIDER_MIN_WIDTH, min(SLIDER_MAX_WIDTH, plot_rect.width - 120))
    slider_x = BTN_START_X
    slider_y = plot_rect.bottom + 20
    slider_rect = pygame.Rect(slider_x, slider_y, slider_width, SLIDER_HEIGHT)

    stop_x = slider_rect.right + STOP_BTN_EXTRA_GAP
    stop_y = slider_rect.centery - BTN_H // 2
    stop_rect = pygame.Rect(stop_x, stop_y, STOP_BTN_WIDTH, BTN_H)

    return {
        "plot_rect": plot_rect,
        "slider_rect": slider_rect,
        "stop_rect": stop_rect,
        "info_x": BTN_START_X,
        "info_y": stop_rect.bottom + 12
    }

def slider_value_to_time(value):
    value = max(0.0, min(1.0, value))
    log_min = math.log10(TIME_WINDOW_MIN)
    log_max = math.log10(TIME_WINDOW_MAX)
    return 10 ** (log_min + value * (log_max - log_min))

def time_to_slider_value(seconds):
    seconds = max(TIME_WINDOW_MIN, min(TIME_WINDOW_MAX, seconds))
    log_min = math.log10(TIME_WINDOW_MIN)
    log_max = math.log10(TIME_WINDOW_MAX)
    return (math.log10(seconds) - log_min) / (log_max - log_min)

def format_time_window(seconds):
    if seconds < 0.01:
        return f"{seconds*1000:.2f} ms"
    if seconds < 1.0:
        return f"{seconds*1000:.1f} ms"
    if seconds < 10:
        return f"{seconds:.2f} s"
    return f"{seconds:.1f} s"

def extract_window(values, sample_rate, window_seconds):
    if not values:
        return []
    needed = max(2, int(sample_rate * window_seconds))
    needed = min(needed, len(values))
    if needed <= 0:
        return []
    return values[-needed:]

def slider_value_from_pos(rect, x):
    if rect.width <= 0:
        return 0.0
    return max(0.0, min(1.0, (x - rect.left) / rect.width))

def resample_values(values, target_len):
    if not values or target_len <= 0:
        return []
    if len(values) == target_len:
        return list(values)
    res = []
    step = len(values) / target_len
    for i in range(target_len):
        idx = int(i * step)
        if idx >= len(values):
            idx = len(values) - 1
        res.append(values[idx])
    return res

def draw_slider(surface, rect, value):
    track_rect = rect.copy()
    track_rect.inflate_ip(0, 6)
    pygame.draw.rect(surface, (35,35,45), track_rect, border_radius=6)
    inner = rect.inflate(0, 2)
    pygame.draw.rect(surface, (90,90,110), inner, border_radius=6)
    pygame.draw.rect(surface, (0,0,0), track_rect, 2, border_radius=6)
    handle_x = rect.left + value * rect.width
    handle = pygame.Rect(0, 0, 16, 26)
    handle.center = (handle_x, track_rect.centery)
    pygame.draw.rect(surface, (200,200,80), handle, border_radius=6)
    pygame.draw.rect(surface, (0,0,0), handle, 2, border_radius=6)

def main():
    global _sim_t
    pygame.init()
    screen_w, screen_h = WIDTH, HEIGHT
    screen = pygame.display.set_mode((screen_w, screen_h), pygame.RESIZABLE)
    pygame.display.set_caption("Osciloscopio - Lectura ADRESH por Serial")
    clock = pygame.time.Clock()

    layout = compute_layout(screen_w, screen_h)

    max_samples = int(BASE_SAMPLE_RATE * TIME_WINDOW_MAX) + RAW_BUFFER_PAD
    initial_fill = min(max_samples, 1000)
    sample_buffer = deque([128]*initial_fill, maxlen=max_samples)

    slider_value = time_to_slider_value(DEFAULT_TIME_WINDOW)
    slider_dragging = False
    running = True
    paused = False

    ser = None
    if HAS_SERIAL:
        ser = open_serial(SERIAL_PORT, BAUDRATE)
        if ser:
            print("Puerto serial abierto:", SERIAL_PORT, BAUDRATE)
        else:
            print("No serial: modo simulador")
    else:
        print("pyserial no disponible: modo simulador")

    current_adresh = 128
    num2, num1, num0 = bin8_to_dec3(current_adresh)

    # --- botón STOP/REANUDAR (no borra la señal, solo congela la adquisición) ---
    stopped = False

    sample_acc = 0.0

    while running:
        dt = clock.tick(FPS) / 1000.0
        layout_dirty = False
        stop_rect_for_events = layout["stop_rect"]
        slider_rect_for_events = layout["slider_rect"]
        for ev in pygame.event.get():
            if ev.type == pygame.QUIT:
                running = False
            elif ev.type == pygame.VIDEORESIZE:
                screen_w = max(WINDOW_MIN_WIDTH, ev.w)
                screen_h = max(WINDOW_MIN_HEIGHT, ev.h)
                screen = pygame.display.set_mode((screen_w, screen_h), pygame.RESIZABLE)
                layout_dirty = True
            elif ev.type == pygame.KEYDOWN:
                if ev.key == pygame.K_SPACE:
                    paused = not paused
            elif ev.type == pygame.MOUSEBUTTONDOWN and ev.button == 1:
                mx,my = ev.pos
                if slider_rect_for_events.inflate(0, 10).collidepoint(mx,my):
                    slider_dragging = True
                    slider_value = slider_value_from_pos(layout["slider_rect"], mx)
                elif stop_rect_for_events.collidepoint(mx,my):
                    stopped = not stopped
            elif ev.type == pygame.MOUSEBUTTONUP and ev.button == 1:
                slider_dragging = False
            elif ev.type == pygame.MOUSEMOTION and slider_dragging:
                slider_value = slider_value_from_pos(layout["slider_rect"], ev.pos[0])

        if layout_dirty:
            layout = compute_layout(screen_w, screen_h)
        plot_rect = layout["plot_rect"]
        slider_rect = layout["slider_rect"]
        stop_rect = layout["stop_rect"]
        info_x = layout["info_x"]
        info_y = layout["info_y"]

        # sample rate de referencia
        sample_rate = BASE_SAMPLE_RATE
        time_window = slider_value_to_time(slider_value)

        # Solo adquirir nuevos datos si no está paused y no está stopped
        if not paused and not stopped:
            # si hay serial: leer todos los bytes disponibles y agregarlos
            if ser:
                try:
                    n = ser.in_waiting if hasattr(ser, 'in_waiting') else 0
                    if n:
                        data = ser.read(n)
                        for b in data:
                            sample_buffer.append(b)
                            current_adresh = b
                            num2, num1, num0 = bin8_to_dec3(current_adresh)
                    else:
                        # si no llegan bytes, mantener última muestra; para evitar quedarse sin movimiento
                        # añadir una copia ocasional según sample_rate para desplazar horizonte
                        sample_acc += dt * sample_rate
                        while sample_acc >= 1.0:
                            sample_buffer.append(current_adresh)
                            sample_acc -= 1.0
                except Exception as e:
                    # si falla el serial, pasar a modo simulador
                    ser = None
                    print("Error serial, entrando en modo simulador:", e)
            else:
                # simulación: generar muestras según sample_rate
                sample_acc += dt * sample_rate
                while sample_acc >= 1.0:
                    s = generate_sim_sample(_sim_t, freq=SIM_FREQ, amp=1.0)
                    _sim_t += 1.0 / sample_rate
                    ad = int(round((s + 1.0) / 2.0 * 255)) & 0xFF
                    sample_buffer.append(ad)
                    current_adresh = ad
                    num2, num1, num0 = bin8_to_dec3(current_adresh)
                    sample_acc -= 1.0

        # DIBUJO
        screen.fill((15,15,25))
        draw_scope_grid(screen, plot_rect, cols=10, rows=8, minor_steps=5)

        raw_values = list(sample_buffer)
        window_samples = extract_window(raw_values, sample_rate, time_window)
        plot_samples = resample_values(window_samples, plot_rect.width)
        draw_trace(screen, plot_rect, plot_samples, color=(0,200,0))

        # indicadores y texto
        font = pygame.font.SysFont('Consolas', 18)

        # --- CÁLCULO DE Vmax, Vmin, Vpp y FRECUENCIA ESTIMADA ---
        vals = window_samples
        if vals:
            # convertir ADC(0..255) a voltaje
            v_vals = [ (b / 255.0) * VREF for b in vals ]
            v_max = max(v_vals)
            v_min = min(v_vals)
            v_pp = v_max - v_min
            v_avg = sum(v_vals) / len(v_vals)

            # estimación de frecuencia por cruces ascendentes del nivel medio
            mid = (v_max + v_min) / 2.0
            crossings = []
            for i in range(1, len(v_vals)):
                if v_vals[i-1] < mid and v_vals[i] >= mid:
                    crossings.append(i)
            if len(crossings) >= 2 and sample_rate > 0:
                diffs = [crossings[i] - crossings[i-1] for i in range(1, len(crossings))]
                avg_period_samples = sum(diffs) / len(diffs)
                freq_est = sample_rate / avg_period_samples
            else:
                freq_est = 0.0
        else:
            v_max = v_min = v_pp = v_avg = 0.0
            freq_est = 0.0
        # --- FIN CÁLCULOS ---

        # Mover ADRESH y NUMs debajo de los botones para que sean visibles
        # Recuadro izquierdo para ADRESH y NUMs
        left_box_w = 360
        left_box_h = 32
        left_box = pygame.Rect(info_x, info_y, left_box_w, left_box_h)
        pygame.draw.rect(screen, (28,28,36), left_box, border_radius=6)               # fondo
        pygame.draw.rect(screen, (70,70,90), left_box, 2, border_radius=6)           # borde

        txt_color = (200,255,200)
        small_color = (200,200,255)
        pad = 8
        # ADRESH a la izquierda
        screen.blit(font.render(f"ADRESH: {current_adresh:03d}", True, txt_color), (left_box.left + pad, left_box.top + 4))

        # Tres recuadros pequeños a la derecha para NUM2, NUM1 y NUM0 (asegura que NUM0 esté en recuadro)
        digit_w = 48
        digit_h = left_box_h - 8
        digit_gap = 6
        # calcular posición X para alinear los tres dígitos al borde derecho del left_box
        digits_x = left_box.right - (digit_w*3 + digit_gap*2) - pad
        digits_y = left_box.top + 4

        for i, val in enumerate((num2, num1, num0)):
            r = pygame.Rect(digits_x + i*(digit_w + digit_gap), digits_y, digit_w, digit_h)
            pygame.draw.rect(screen, (20,20,30), r, border_radius=4)
            pygame.draw.rect(screen, (70,70,90), r, 2, border_radius=4)
            txt = font.render(str(val), True, small_color)
            tx = r.left + (r.width - txt.get_width())//2
            ty = r.top + (r.height - txt.get_height())//2
            screen.blit(txt, (tx, ty))

        # Recuadros para Vmax, Vpp y Frecuencia (apilados, derecha)
        info2_x = plot_rect.right - 300
        info2_y = plot_rect.bottom + 8
        metric_w = 160
        metric_h = 28
        spacing = 6

        metrics = [
            (f"Vmax: {v_max:.3f} V", txt_color),
            (f"Vmin: {v_min:.3f} V", txt_color),
            (f"Vmed: {v_avg:.3f} V", txt_color),
            (f"Vpp:  {v_pp:.3f} V", txt_color),
            (f"Frec: {freq_est:.2f} Hz", txt_color)
        ]

        for i, (label, color) in enumerate(metrics):
            r = pygame.Rect(info2_x, info2_y + i*(metric_h + spacing), metric_w, metric_h)
            pygame.draw.rect(screen, (28,28,36), r, border_radius=6)
            pygame.draw.rect(screen, (70,70,90), r, 2, border_radius=6)
            screen.blit(font.render(label, True, color), (r.left + 8, r.top + 4))

        # Slider de ventana temporal
        slider_label = f"Ventana visible: {format_time_window(time_window)}"
        screen.blit(font.render(slider_label, True, (220,220,180)), (slider_rect.left, slider_rect.top - 22))
        draw_slider(screen, slider_rect, slider_value)

        # dibujar botón STOP/REANUDAR (label indica acción disponible)
        stop_label = "RUN" if not stopped else "STOP"
        # si stopped==True -> botón muestra "STOP" (significa está detenido y al pulsar volverá a RUN)
        # para que sea más intuitivo mostramos la acción siguiente (RUN) cuando detenido
        draw_button(screen, stop_rect, stop_label, active=stopped)
        # indicador de estado
        state_text = "STOPPED" if stopped else ("PAUSED" if paused else "RUNNING")
        small_font = pygame.font.SysFont('Consolas', 14)
        screen.blit(small_font.render(state_text, True, (240,180,180) if stopped else (180,180,180)), (stop_rect.left, stop_rect.top - 22))

        # leyenda de ayuda
        small = pygame.font.SysFont('Consolas', 14)
        screen.blit(small.render("Arrastra el slider para ajustar ventana (1 ms a 60 s). Espacio pausa. Ajustar SERIAL_PORT si se usa hardware.", True, (180,180,180)), (40, screen_h-30))

        pygame.display.flip()

    if ser:
        ser.close()
    pygame.quit()
    sys.exit()

if __name__ == '__main__':
    main()
#-----------------------------------------------------------------------------------------------    
# para ejecutar el script usar:
# python "C:\Users\cjcar\Documents\Digital_2\TP's\TP_FINAL\Multimetro\Interfaz\Osciloscopio.py"
#-----------------------------------------------------------------------------------------------
