;========================================================
; Voltímetro 0.00 .. 5.00 (muestra 000..500 con DP fijo en el primer display)
; ADC: 8 bits (ADRESH, ADFM=0), AN0 (RA0)
; Displays: PORTD (segmentos, cátodo común)
;           RB7=unidades, RB6=decenas, RB5=centenas (activos en 0)
; DP fijo en el display de centenas (izquierdo) -> X.XX
; PIC16F887 @ 4 MHz
;========================================================
        LIST    P=16F887
        #include <p16f887.inc>

;------------------------------- Config -------------------------------
        __CONFIG _CONFIG1, _FOSC_XT & _WDTE_OFF & _PWRTE_OFF & _MCLRE_ON & _CP_OFF & _CPD_OFF & _BOREN_ON & _IESO_ON & _FCMEN_ON & _LVP_OFF
        __CONFIG _CONFIG2, _BOR4V_BOR40V & _WRT_OFF

;------------------------------ Variables (Banco 0) -------------------
W_TEMP          EQU     0x70
STATUS_TEMP     EQU     0x71
PCLATH_TEMP     EQU     0x72

INDEX           EQU     0x20    ; 0..2 (0=unid RB7, 1=dec RB6, 2=cent RB5)
NUM0            EQU     0x21    ; unidades
NUM1            EQU     0x22    ; decenas
NUM2            EQU     0x23    ; centenas

ADC8            EQU     0x24
TMP             EQU     0x25
C1              EQU     0x26
DIGIT           EQU     0x27

SUM_H          EQU     0x2C    ; suma de 8 muestras (MSB)
SUM_L          EQU     0x2D    ; suma de 8 muestras (LSB)

CV_H            EQU     0x28    ; CV = 0..500 (16-bit)
CV_L            EQU     0x29
TEN_H           EQU     0x2A    ; 10*N (16-bit)
TEN_L            EQU     0x2B

;------------------------------ Constantes ----------------------------
ALL_OFF_B       EQU     0xE0    ; RB7=1, RB6=1, RB5=1 (apagados)
MASK_RB7_ON     EQU     0x60    ; RB7 bajo (unidades)
MASK_RB6_ON     EQU     0xA0    ; RB6 bajo (decenas)
MASK_RB5_ON     EQU     0xC0    ; RB5 bajo (centenas)

;------------------------------- Vectores -----------------------------
            ORG     0x0000
            GOTO    INICIO

            ORG     0x0004
            GOTO    ISR_TMR0

;--------------------- Tablas 7-seg (cátodo común) --------------------
TABLA_DISPLAY:
    ADDWF   PCL, F
    RETLW   B'00111111' ; 0
    RETLW   B'00000110' ; 1
    RETLW   B'01011011' ; 2
    RETLW   B'01001111' ; 3
    RETLW   B'01100110' ; 4
    RETLW   B'01101101' ; 5
    RETLW   B'01111101' ; 6
    RETLW   B'00000111' ; 7
    RETLW   B'01111111' ; 8
    RETLW   B'01101111' ; 9

; Mismos patrones con punto decimal (bit7=1) para el PRIMER display
TABLA_DISPLAY_DP:
    ADDWF   PCL, F
    RETLW   B'10111111' ; 0.
    RETLW   B'10000110' ; 1.
    RETLW   B'11011011' ; 2.
    RETLW   B'11001111' ; 3.
    RETLW   B'11100110' ; 4.
    RETLW   B'11101101' ; 5.
    RETLW   B'11111101' ; 6.
    RETLW   B'10000111' ; 7.
    RETLW   B'11111111' ; 8.
    RETLW   B'11101111' ; 9.

;=============================== Inicio ===============================
INICIO:
    ; Limpiar puertos
    CLRF    PORTD
    CLRF    PORTA
    CLRF    PORTB

    ; ---------- Config analógico/digital ----------
    BANKSEL ANSEL
    MOVLW   b'00000001'         ; AN0 analógico, resto digital
    MOVWF   ANSEL
    CLRF    ANSELH

    ; Deshabilitar comparadores
    BANKSEL CM1CON0
    CLRF    CM1CON0
    CLRF    CM2CON0

    ; ---------- TRIS ----------
    BANKSEL TRISD
    CLRF    TRISD

    BANKSEL TRISB
    MOVLW   b'00011111'
    MOVWF   TRISB

    BANKSEL TRISC
    BCF     TRISC,6            ; RC6 = TX (salida)
    BSF     TRISC,7            ; RC7 = RX (entrada)

    BANKSEL TRISA
    MOVLW   b'11111111'
    MOVWF   TRISA

    ; ---------- UART TX (19200 bps, Fosc=4 MHz) ----------
    BANKSEL SPBRG
    CLRF    SPBRGH
    MOVLW   .12
    MOVWF   SPBRG

    BANKSEL TXSTA
    MOVLW   b'00100100'        ; BRGH=1, TXEN=1, modo async
    MOVWF   TXSTA

    BANKSEL RCSTA
    MOVLW   b'10000000'        ; SPEN=1
    MOVWF   RCSTA

    ; ---------- Timer0 (multiplex) ----------
    BANKSEL OPTION_REG
    MOVLW   b'00000101'         ; PS=1:64
    MOVWF   OPTION_REG
    BANKSEL TMR0
    MOVLW   D'206'              ; ~1.5 ms
    MOVWF   TMR0

    ; ---------- ADC ----------
    ; ADFM=0 (left-justified), ADON=1, canal AN0, Fosc/8
    BANKSEL ADCON1
    CLRF    ADCON1              ; ADFM=0 (left), Vref=Vdd/Vss
    BANKSEL ADCON0
    MOVLW   b'01000001'         ; ADCS=01 (Fosc/8), CHS=0000 (AN0), ADON=1
    MOVWF   ADCON0

    ; ---------- Interrupciones ----------
    BANKSEL INTCON
    BSF     INTCON, TMR0IE
    BSF     INTCON, GIE

    ; ---------- Variables ----------
    BANKSEL INDEX
    CLRF    INDEX
    CLRF    NUM0
    CLRF    NUM1
    CLRF    NUM2

;========================= Bucle principal ============================
MAIN_LOOP:
    ; Promediar 8 conversiones para suavizar la lectura
    BANKSEL SUM_L
    CLRF    SUM_L
    CLRF    SUM_H
    MOVLW   .8
    MOVWF   TMP

SAMPLE_ADC:
    CALL    ACQ_DELAY_10US
    BANKSEL ADCON0
    BSF     ADCON0, GO_DONE

WAIT_ADC:
    BTFSC   ADCON0, GO_DONE
    GOTO    WAIT_ADC

    BANKSEL ADRESH
    MOVF    ADRESH, W
    BANKSEL SUM_L
    ADDWF   SUM_L, F
    BTFSC   STATUS, C
    INCF    SUM_H, F

    DECFSZ  TMP, F
    GOTO    SAMPLE_ADC

    ; promedio = suma / 8
    BCF     STATUS, C
    RRF     SUM_H, F
    RRF     SUM_L, F
    BCF     STATUS, C
    RRF     SUM_H, F
    RRF     SUM_L, F
    BCF     STATUS, C
    RRF     SUM_H, F
    RRF     SUM_L, F

    MOVF    SUM_L, W
    BANKSEL ADC8
    MOVWF   ADC8

    ; enviar la muestra promedio por UART
    MOVF    ADC8, W
    CALL    UART_SEND

    ; 4) Escalar N(0..255) -> CV(0..500) con:
    ;    CV = (N<<1) - ((10*N + 128)>>8)    [? N*500/255 con redondeo]
    ;
    ; CV = 2*N (16 bits)
    CLRF    CV_H
    MOVF    ADC8, W
    MOVWF   CV_L
    BCF     STATUS, C
    RLF     CV_L, F
    RLF     CV_H, F

    ; TEN = 10*N = 8*N + 2*N  (16 bits)
    CLRF    TEN_H
    MOVF    ADC8, W
    MOVWF   TEN_L              ; Ten = N
    BCF     STATUS, C
    RLF     TEN_L, F           ; *2
    RLF     TEN_H, F
    BCF     STATUS, C
    RLF     TEN_L, F           ; *4
    RLF     TEN_H, F
    BCF     STATUS, C
    RLF     TEN_L, F           ; *8
    RLF     TEN_H, F
    ; +2*N
    MOVF    ADC8, W
    MOVWF   TMP
    BCF     STATUS, C
    RLF     TMP, F             ; TMP = 2*N
    ADDWF   TEN_L, F
    BTFSC   STATUS, C
    INCF    TEN_H, F

    ; Q = (TEN + 128) >> 8
    MOVLW   .128
    ADDWF   TEN_L, F
    BTFSC   STATUS, C
    INCF    TEN_H, F
    MOVF    TEN_H, W           ; W = Q

    ; CV = CV - Q  (16b - 8b)
    SUBWF   CV_L, F
    BTFSC   STATUS, C
    GOTO    CV_SUB_OK
    DECF    CV_H, F
CV_SUB_OK:

; 5) Separar CV (0..500) en NUM2 (centenas), NUM1 (decenas), NUM0 (unidades)
SPLIT_DEC3:
    CLRF    NUM2
    CLRF    NUM1
    CLRF    NUM0

; centenas: restar 100 mientras alcance (manejo 16-bit)
CENT_LOOP:
    ; ¿CV >= 100? (si CV_H>0 o CV_L>=100)
    MOVF    CV_H, W
    BTFSS   STATUS, Z
    GOTO    SUB_CENT
    MOVLW   .100
    SUBWF   CV_L, W            ; 100 - CV_L
    BTFSS   STATUS, C          ; C=0 => CV_L >= 100
    GOTO    TENS               ; si <100, pasar a decenas

SUB_CENT:
    MOVLW   .100
    SUBWF   CV_L, F
    BTFSS   STATUS, C
    DECF    CV_H, F            ; pedir prestado si hubo borrow
    INCF    NUM2, F
    GOTO    CENT_LOOP

; decenas (ahora <=99)
TENS:
    MOVLW   .10
    SUBWF   CV_L, F
    BTFSS   STATUS, C
    GOTO    TENS_FIX
    INCF    NUM1, F
    GOTO    TENS
TENS_FIX:
    MOVLW   .10
    ADDWF   CV_L, F

; unidades
    MOVF    CV_L, W
    MOVWF   NUM0

    GOTO    MAIN_LOOP

;===================== Interrupción Timer0 (multiplex) =====================
ISR_TMR0:
    MOVWF   W_TEMP
    SWAPF   STATUS, W
    MOVWF   STATUS_TEMP
    MOVF    PCLATH, W
    MOVWF   PCLATH_TEMP
    ; Recargar TMR0
    BANKSEL TMR0
    MOVLW   D'206'
    MOVWF   TMR0
    BCF     INTCON, TMR0IF

    ; Apagar todos los dígitos (activos en 0)
    BANKSEL PORTB
    MOVLW   ALL_OFF_B
    MOVWF   PORTB

    ; Seleccionar valor del dígito actual
    BANKSEL INDEX
    MOVLW   NUM0
    ADDWF   INDEX, W
    MOVWF   FSR
    MOVF    INDF, W
    ANDLW   0x0F
    MOVWF   DIGIT

    ; Si INDEX==2 (centenas/izquierdo) -> usar tabla con DP
    MOVF    INDEX, W
    XORLW   0x02
    BTFSS   STATUS, Z
    GOTO    SIN_DP
CON_DP:
    MOVF    DIGIT, W
    CALL    TABLA_DISPLAY_DP
    GOTO    WRITE_SEG

SIN_DP:
    MOVF    DIGIT, W
    CALL    TABLA_DISPLAY
    GOTO    WRITE_SEG

WRITE_SEG:
    BANKSEL PORTD
    MOVWF   PORTD

    ; Habilitar dígito correspondiente (RB7/RB6/RB5 en bajo)
    BANKSEL INDEX
    MOVF    INDEX, W
    CALL    DIG_MASK_TABLE
    BANKSEL PORTB
    MOVWF   PORTB

    ; Avanzar índice 0..2
    BANKSEL INDEX
    INCF    INDEX, F
    MOVF    INDEX, W
    XORLW   0x03
    BTFSC   STATUS, Z
    CLRF    INDEX

    ; Restaurar contexto
    SWAPF   PCLATH_TEMP, W
    MOVWF   PCLATH
    SWAPF   STATUS_TEMP, W
    MOVWF   STATUS
    SWAPF   W_TEMP, F
    SWAPF   W_TEMP, W
    RETFIE

; --- Devuelve en W la máscara de PORTB según INDEX (0..2) ---
DIG_MASK_TABLE:
    ADDWF   PCL, F
    RETLW   MASK_RB5_ON     ; centenas
    RETLW   MASK_RB6_ON     ; decenas
    RETLW   MASK_RB7_ON     ; unidades

;====================== Subrutinas de apoyo ==========================
; ~10 us @ 4 MHz (aprox)
ACQ_DELAY_10US:
    MOVLW   .10
    MOVWF   C1
ADLY_L:
    NOP
    DECFSZ  C1, F
    GOTO    ADLY_L
    RETURN

UART_SEND:
    BANKSEL PIR1
WAIT_TX:
    BTFSS   PIR1, TXIF
    GOTO    WAIT_TX
    BANKSEL TXREG
    MOVWF   TXREG
    RETURN

            END
