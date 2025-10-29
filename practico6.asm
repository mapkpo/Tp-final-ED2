;-----------------------------------------------
    LIST    P=16F887
    #include <p16f887.inc>

;--------------------------------- Config -------------------------------------
    __CONFIG _CONFIG1, _FOSC_XT & _WDTE_OFF & _PWRTE_OFF & _MCLRE_ON & _CP_OFF & _CPD_OFF & _BOREN_ON & _IESO_ON & _FCMEN_ON & _LVP_OFF
    __CONFIG _CONFIG2, _BOR4V_BOR40V & _WRT_OFF

;------------------------------- Variables ------------------------------------
; Banco 0, GPR
W_TEMP          EQU     0x70
STATUS_TEMP     EQU     0x71
PCLATH_TEMP     EQU     0x72

INDEX           EQU     0x20     ; índice de display (0..2)
NUM0            EQU     0x21     ; unidades
NUM1            EQU     0x22     ; decenas
NUM2            EQU     0x23     ; centenas

ADC8            EQU     0x24     ; valor 0..255 leído (ADRESH)
TMP             EQU     0x25     ; trabajo para conversión
C1              EQU     0x26     ; contador genérico

;-------------------------------- Constantes ----------------------------------
; Habilitación por bajo en RB7, RB6, RB5
ALL_OFF_B       EQU     0xF0     ; RB7=1, RB6=1, RB5=1 (todos apagados)
MASK_RB7_ON     EQU     0x70     ; RB7=0, RB6=1, RB5=1 -> dígito 0 (unidades)
MASK_RB6_ON     EQU     0xB0     ; RB7=1, RB6=0, RB5=1 -> dígito 1 (decenas)
MASK_RB5_ON     EQU     0xD0     ; RB7=1, RB6=1, RB5=0 -> dígito 2 (centenas)

;--------------------------------- Vectores -----------------------------------
            ORG     0x0000
            GOTO    INICIO

            ORG     0x0004
            GOTO    ISR_TMR0

;---------------------------- Tabla 7 segmentos -------------------------------
; (cátodo común: segmentos activos en ?1?)
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

;------------------------------- Inicio ---------------------------------------
INICIO:
    ; PORTs a 0
    CLRF    PORTD
    CLRF    PORTA
    CLRF    PORTB

    ; ---------- Config analógico/digital ----------
    BANKSEL ANSEL
    MOVLW   b'00000001'         ; AN0 analógico, resto de PORTA digital
    MOVWF   ANSEL
    CLRF    ANSELH              ; Todo PORTB digital

    ; Deshabilitar comparadores
    BANKSEL CM1CON0
    CLRF    CM1CON0
    CLRF    CM2CON0

    ; ---------- TRIS ----------
    BANKSEL TRISD
    CLRF    TRISD               ; RD0..RD7 salidas (segmentos)

    BANKSEL TRISB
    MOVLW   b'00011111'         ; RB0..RB4 entradas (no los tocamos)
                                ; RB5..RB7 salidas (enable de displays)
    MOVWF   TRISB

    BANKSEL TRISA
    MOVLW   b'11111111'         ; Dejo PORTA como entradas; RA0 será AN0
    MOVWF   TRISA

    ; ---------- Timer0 para multiplex ----------
    BANKSEL OPTION_REG
    MOVLW   b'00000111'         ; prescaler 1:256 a TMR0, Fosc/4
    MOVWF   OPTION_REG
    BANKSEL TMR0
    MOVLW   D'237'              ; ~4.864 ms entre interrupciones a 4 MHz
    MOVWF   TMR0

    ; ---------- ADC ----------
    ; ADON=1, canal AN0, reloj ADC = Fosc/8 (TAD=2us)
    BANKSEL ADCON0
    MOVLW   b'01000001'         ; ADCS=01 (Fosc/8), CHS=0000 (AN0), ADON=1
    MOVWF   ADCON0
    BANKSEL ADCON1
    CLRF    ADCON1              ; ADFM=0 (left), Vref=Vdd/Vss

    ; ---------- Interrupciones ----------
    BANKSEL INTCON
    BSF     INTCON, TMR0IE
    BSF     INTCON, GIE

    ; ---------- Init variables ----------
    BANKSEL INDEX
    CLRF    INDEX
    CLRF    NUM0
    CLRF    NUM1
    CLRF    NUM2

;------------------------------- Bucle principal ------------------------------
MAIN_LOOP:
    ; 1) Pequeño tiempo de adquisición tras seleccionar AN0
    CALL    ACQ_DELAY_10US

    ; 2) Disparar conversión (no al mismo tiempo que ADON)
    BANKSEL ADCON0
    BSF     ADCON0, GO_DONE

WAIT_ADC:
    BTFSC   ADCON0, GO_DONE
    GOTO    WAIT_ADC

    ; 3) Tomar 8 bits (0..255) de ADRESH (left-justified => 10 bits >> 2)
    BANKSEL ADRESH
    MOVF    ADRESH, W
    MOVWF   ADC8

    ; 4) Convertir a decimal y volcar a NUM2..NUM0
    CALL    BIN8_TO_DEC3

    GOTO    MAIN_LOOP

;--------------------------- Interrupción Timer0 ------------------------------
ISR_TMR0:
    ; Guardar contexto
    MOVWF   W_TEMP
    SWAPF   STATUS, W
    MOVWF   STATUS_TEMP
    MOVF    PCLATH, W
    MOVWF   PCLATH_TEMP

    ; Recargar TMR0
    BANKSEL TMR0
    MOVLW   D'237'
    MOVWF   TMR0
    BCF     INTCON, TMR0IF

    ; Apagar todos los dígitos (activos en 0) en PORTB
    BANKSEL PORTB
    MOVLW   ALL_OFF_B
    MOVWF   PORTB

    ; Poner segmentos del dígito actual en PORTD
    ; NUM0 (unid), NUM1 (dec), NUM2 (cent)
    BANKSEL INDEX
    MOVLW   NUM0
    ADDWF   INDEX, W
    MOVWF   FSR
    MOVF    INDF, W
    ANDLW   0x0F
    CALL    TABLA_DISPLAY
    BANKSEL PORTD
    MOVWF   PORTD

    ; Habilitar dígito correspondiente (RB7/RB6/RB5 -> activo en 0)
    BANKSEL INDEX
    MOVF    INDEX, W
    CALL    DIG_MASK_TABLE      ; W sale con la máscara (solo bits 7..5)
    BANKSEL PORTB
    MOVWF   PORTB               ; encender ese dígito

    ; Avanzar índice 0..2
    BANKSEL INDEX
    INCF    INDEX, F
    MOVF    INDEX, W
    XORLW   0x03                ; ¿llegó a 3?
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

; --- Devuelve en W la máscara de PORTB según INDEX (0..2) --------------------
DIG_MASK_TABLE:
    ; INDEX en W: 0->RB7, 1->RB6, 2->RB5
    ADDWF   PCL, F
    RETLW   MASK_RB7_ON     ; 0 -> RB7 bajo (unidades)
    RETLW   MASK_RB6_ON     ; 1 -> RB6 bajo (decenas)
    RETLW   MASK_RB5_ON     ; 2 -> RB5 bajo (centenas)

;------------------------ Subrutinas de apoyo -------------------------------

; ~10 us a 4 MHz (aprox)
ACQ_DELAY_10US:
    MOVLW   .10
    MOVWF   C1
ACQ_DLY_L:
    NOP
    DECFSZ  C1, F
    GOTO    ACQ_DLY_L
    RETURN

; Convierte ADC8 (0..255) a tres dígitos decimales (NUM2=cent, NUM1=dec, NUM0=uni)
BIN8_TO_DEC3:
    ; TMP = ADC8
    MOVF    ADC8, W
    MOVWF   TMP
    CLRF    NUM2
    CLRF    NUM1
    CLRF    NUM0

; centenas
B2D_HUND_LOOP:
    MOVLW   .100
    SUBWF   TMP, F          ; TMP = TMP - 100
    BTFSS   STATUS, C       ; ¿borrow? (TMP < 0)?
    GOTO    B2D_HUND_FIX
    INCF    NUM2, F
    GOTO    B2D_HUND_LOOP
B2D_HUND_FIX:
    MOVLW   .100
    ADDWF   TMP, F          ; deshacer último
; decenas
B2D_TENS_LOOP:
    MOVLW   .10
    SUBWF   TMP, F
    BTFSS   STATUS, C
    GOTO    B2D_TENS_FIX
    INCF    NUM1, F
    GOTO    B2D_TENS_LOOP
B2D_TENS_FIX:
    MOVLW   .10
    ADDWF   TMP, F
; unidades
    MOVF    TMP, W
    MOVWF   NUM0
    RETURN

            END
