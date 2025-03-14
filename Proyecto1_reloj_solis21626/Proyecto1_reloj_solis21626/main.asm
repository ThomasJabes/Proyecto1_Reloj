//*********************************************************************
// Universidad del Valle de Guatemala
// IE2023: Programación de Microcontroladores
// Author : Thomas Solis
// Proyecto: PROYECTO 1
// Descripción: Visualizador de Reloj, Fecha y Alarma. 
// Hardware: ATmega328p
// Created: 17/02/2025 16:45:54
//*********************************************************************
// Encabezado
//******************************************************************

;***************************************************************************
; Configuración de Hardware
;***************************************************************************
.include "M328PDEF.inc"
.cseg

; Variables
.def cont500ms = R20  ; Contador para 500ms
.def estado = R16     ; Estados
.def useg = R21  ; Unidades de segundos
.def dseg = R22 ; Decenas de segundo
.def umin = R23 ; Unidades de minutos 
.def dmin = R24 ; Decenas de minutos 
.def uhor = R25 ; Unidad de hora 
.def dhor = R26 ; Decena de horas 
.def cont1s = R19     ; Contador de 1 segundo
.def cont60s = R18    ; Contador de 60 segundos
.def mes_u = R0  ; Unidades del mes
.def mes_d = R1      ; Decenas del mes
.def dia_u = R2     ; Unidades del día
.def dia_d = R3      ; Decenas del día
.def alar_hor_d = R4  ; Decenas de horas de la alarma
.def alar_hor_u = R5  ; Unidades de horas de la alarma
.def alar_min_d = R6  ; Decenas de minutos de la alarma
.def alar_min_u = R7  ; Unidades de minutos de la alarma
.def alarma_activa = R8  ; 0 = OFF, 1 = ON


.org 0x00
    jmp MAIN          ; Vector principal

.org 0x0008         ; Vector de interrupción para PCINT1 (BOTONES)
    jmp ISR_BOTONES

.org 0x0020           ; Vector de interrupción para Timer0 Overflow
    jmp ISR_TIMER0_OVF

;***************************************************************************
; MAIN
;***************************************************************************
MAIN:
    ; Configuración del Stack
    LDI R16, LOW(RAMEND)
    OUT SPL, R16
    LDI R17, HIGH(RAMEND)
    OUT SPH, R17

;***************************************************************************
; TABLA 
;***************************************************************************
T7S: .DB 0x7E, 0x30, 0x6D, 0x79, 0x33, 0x5B, 0x5F, 0x70, 0x7F, 0x7B   ; (0-9)

;***************************************************************************
; Configuracion de pines
;***************************************************************************
SETUP: 
	; Configurar pines del DISPLAY (PD0 - PD6 como salida, dejando PD7 sin cambios)
	LDI R16, 0x7F  
	OUT DDRD, R16  

    ; Configurar pines para controlar los dígitos del display (PB0 - PB3 como salida)
    LDI R16, 0x3F
    OUT DDRB, R16

    ; Configurar botones de entrada (PC2, PC3 y PC4 como entrada)
    LDI R16, 0b00011000  ; PC3 (Cambio Hora/Fecha) y PC4 como entrada
    OUT DDRC, R16

    ; Activar pull-up en los botones (PC0, PC1, PC2 y PC3)
    LDI R16, 0b00001111  ; Pull-up en PC0, PC1, PC2 y PC3
    OUT PORTC, R16

    ; Apagar los dos puntos (leds) inicialmente
    CBI PORTC, PC4  

    ; PB5: LED para configuración de hora
    SBI DDRB, PB5   
    CBI PORTB, PB5  

    ; PB4: LED para configuración de fecha
    SBI DDRB, PB4   
    CBI PORTB, PB4  

    ; PD7: LED para configuración de alarma
    SBI DDRD, PD7  
    CBI PORTD, PD7  

    ; Configurar PC5 como salida para el buzzer
	SBI DDRC, PC5   ; Configurar PC5 como salida
	CBI PORTC, PC5  ; Asegurar que el buzzer inicia apagado
	
    ; Inicialización del Timer0
    CALL Init_T0

    ; CONFIGURAR INTERRUPCIONES POR PULSADORES
    LDI R16, (1 << PCINT11) | (1 << PCINT10) | (1 << PCINT9) | (1 << PCINT8) ; Habilitar interrupciones en PC3, PC2, PC1 y PC0
    STS PCMSK1, R16

    LDI R16, (1 << PCIE1) ; Habilitar interrupciones en PCINT
    STS PCICR, R16

    ; INICIALIZAR VARIABLES DEL RELOJ (00:00)
    CLR uhor
    CLR dhor
    CLR umin
    CLR dmin

    ; FECHA (01/01)
    LDI R28, 0
    MOV dia_d, R28
    LDI R28, 1
    MOV dia_u, R28
	
    LDI R28, 0
    MOV mes_d, R28
    LDI R28, 1
    MOV mes_u, R28

	; ALARMA (00:00)
    LDI R28, 0
    MOV alar_hor_d, R28  ; Decenas de horas de la alarma = 0
	LDI R28, 0
    MOV alar_hor_u, R28  ; Unidades de horas de la alarma = 0
	LDI R28, 0
    MOV alar_min_d, R28  ; Decenas de minutos de la alarma = 0
	LDI R28, 0
    MOV alar_min_u, R28  ; Unidades de minutos de la alarma = 0

    LDI R29, 0
    MOV alarma_activa, R29  ; Estado de la alarma = OFF (0)

    ; INICIALIZAR CONTADORES
    CLR cont1s
    CLR cont60s
    CLR estado  ; Estado inicial: 0000 (visualización)

    ; HABILITAR INTERRUPCIONES GLOBALES
    SEI

;***************************************************************************
; LOOP
;***************************************************************************
LOOP:
    CPI estado, 0
    BREQ ESTADO_0000   ; Estado de visualización normal (HH:MM)

    CPI estado, 1
    BREQ ESTADO_0001   ; Estado de modificación de horas

    CPI estado, 2
    BREQ ESTADO_0002   ; Estado de modificación de minutos

    CPI estado, 3
    BREQ ESTADO_0003   ; Estado de visualización de fecha (DD/MM)

    CPI estado, 4
    BREQ ESTADO_0004   ; Estado de configuración del mes

    CPI estado, 5
    BREQ ESTADO_0005   ; Estado de configuración del día

    CPI estado, 6
    BREQ ESTADO_0006   ; Estado de visualización de la alarma (HH:MM)

    CPI estado, 7
    BREQ ESTADO_0007   ; Estado de configuración de minutos de la alarma

    CPI estado, 8
    BREQ ESTADO_0008   ; Estado de configuración de horas de la alarma

    RJMP LOOP          ; Mantener el ciclo activo

;***************************************************************************
; Mostrar HH:MM, DD/MM o la Alarma en el Display
;***************************************************************************
ESTADO_0000:    ; Modo Normal (Visualización HH:MM)
    CALL DHOR_DISPLAY
    CALL UHOR_DISPLAY
    CALL DMIN_DISPLAY
    CALL UMIN_DISPLAY
    RJMP LOOP

ESTADO_0001:    ; Modo Configuración de Horas (HH:XX)
    CALL DHOR_DISPLAY
    CALL UHOR_DISPLAY
    CBI PORTB, PB2  ; Apagar decenas de minutos
    CBI PORTB, PB3  ; Apagar unidades de minutos
    RJMP LOOP

ESTADO_0002:    ; Modo Configuración de Minutos (XX:MM)
    CBI PORTB, PB0  ; Apagar decenas de horas
    CBI PORTB, PB1  ; Apagar unidades de horas
    CALL DMIN_DISPLAY
    CALL UMIN_DISPLAY
    RJMP LOOP

ESTADO_0003:    ; Modo Visualización de Fecha (DD/MM)
    CALL DDIA_DISPLAY   ; Decenas de día
    CALL UDIA_DISPLAY   ; Unidades de día
    CALL DMES_DISPLAY   ; Decenas de mes
    CALL UMES_DISPLAY   ; Unidades de mes
    RJMP LOOP

ESTADO_0004:    ; Modo Configuración de Mes (XX/MM)
    CBI PORTB, PB0      ; Apagar decenas de días
    CBI PORTB, PB1      ; Apagar unidades de días
    CALL DMES_DISPLAY   ; Decenas de mes
    CALL UMES_DISPLAY   ; Unidades de mes
    RJMP LOOP

ESTADO_0005:    ; Modo Configuración de Día (DD/XX)
    CALL DDIA_DISPLAY   ; Decenas de día
    CALL UDIA_DISPLAY   ; Unidades de día
    CBI PORTB, PB2      ; Apagar decenas de mes
    CBI PORTB, PB3      ; Apagar unidades de mes
    RJMP LOOP

ESTADO_0006:    ; Modo Visualización de la Alarma (HH:MM)
    CALL DHOR_ALARM_DISPLAY  ; Decenas de hora de la alarma (R4)
    CALL UHOR_ALARM_DISPLAY  ; Unidades de hora de la alarma (R5)
    CALL DMIN_ALARM_DISPLAY  ; Decenas de minuto de la alarma (R6)
    CALL UMIN_ALARM_DISPLAY  ; Unidades de minuto de la alarma (R7)
    RJMP LOOP

ESTADO_0007:    ; Modo Configuración de Minutos de la Alarma (XX:MM)
    CBI PORTB, PB0  ; Apagar decenas de horas
    CBI PORTB, PB1  ; Apagar unidades de horas
    CALL DMIN_ALARM_DISPLAY
    CALL UMIN_ALARM_DISPLAY
    RJMP LOOP

ESTADO_0008:    ; Modo Configuración de Horas de la Alarma (HH:XX)
    CALL DHOR_ALARM_DISPLAY
    CALL UHOR_ALARM_DISPLAY
	CBI PORTB, PB2  ; Apagar decenas de minutos
    CBI PORTB, PB3  ; Apagar unidades de minutos
    RJMP LOOP

;***************************************************************************
; ISR BOTONES 
;***************************************************************************
ISR_BOTONES:
    IN R17, PINC  ; Leer el puerto de los botones

    ; Si se presiona PC2, cambiar de estado Y apagar la alarma si está activa
    SBIS PINC, PC2  
    CALL Gestionar_PC2  ; Llamar a la función que maneja ambas acciones

    ; Si se presiona PC3, cambiar entre Hora (0000), Fecha (0003) y Alarma (0006)
    SBIS PINC, PC3         
    CALL Cambiar_Estado_Principal

    ; Asegurar que PC0 (Incrementar) y PC1 (Decrementar) solo funcionen en los estados adecuados
    CPI estado, 0
    BREQ RET_ISR
    CPI estado, 3
    BREQ RET_ISR
    CPI estado, 6
    BREQ RET_ISR  ; En estado de visualización de alarma, no se cambia con PC0 o PC1

    ; Detectar botón de incremento
    SBIS PINC, PC0  
    CALL Incrementar

    ; Detectar botón de decremento
    SBIS PINC, PC1  
    CALL Decrementar

RET_ISR:
    RETI  ; Salir de la interrupción


;***************************************************************************
; Función que maneja PC2: Cambia de estado y apaga la alarma si está activa
;***************************************************************************
Gestionar_PC2:
    SBIC PORTC, PC5   ; Si la alarma está activada (PC5 en ALTO)  
    CALL APAGAR_ALARMA  ; Apagar la alarma  

    CALL Cambiar_Estado  ; Seguir con el cambio de estado  
    RET

APAGAR_ALARMA:
    CLR alarma_activa  ; APAGAR ALARMA
    CBI PORTC, PC5     ;  APAGAR BUZZER
    RETI


;***************************************************************************
; Función para cambiar entre Hora (0000), Fecha (0003) y Alarma (0006)
;***************************************************************************
Cambiar_Estado_Principal:
    CPI estado, 0          
    BREQ Cambiar_A_Fecha   
    CPI estado, 3          
    BREQ Cambiar_A_Alarma  
    CPI estado, 6
    BREQ Cambiar_A_Hora    ; Si estaba en alarma, regresar a hora normal
    RET                    

Cambiar_A_Fecha:
    LDI estado, 3          
    RET

Cambiar_A_Alarma:
    LDI estado, 6          
    RET

Cambiar_A_Hora:
    CLR estado             
    RET


;***************************************************************************
; Función para cambiar de estado (Horas/Minutos o Meses/Días o Alarma)
;***************************************************************************
Cambiar_Estado:
    CPI estado, 3          
    BREQ Cambiar_Config_Fecha   ; Si estamos en 0003 (fecha), cambiar a configuración de fecha

    CPI estado, 4          
    BREQ Cambiar_A_Dia    ; Si estamos en 0004 (config. de mes), pasar a config. de día

    CPI estado, 5          
    BREQ Cambiar_A_Visualizar_Fecha    ; Si estamos en 0005 (config. de día), regresar a fecha

    CPI estado, 6          
    BREQ Cambiar_Config_Alarma   ; Si estamos en 0006 (alarma), pasar a config. de alarma

    CPI estado, 7          
    BREQ Cambiar_Config_Alarma_Horas   ; Si estamos en 0007 (alarma minutos), pasar a alarma horas

    CPI estado, 8          
    BREQ Cambiar_A_Visualizar_Alarma   ; Si estamos en 0008 (alarma horas), regresar a visualización de alarma

    INC estado              ; Si no está en ninguno de los anteriores, simplemente incrementa
    CPI estado, 3          
    BRNE SKIP_RESET        
    CLR estado              ; Si llega a estado 3, reiniciarlo a 0

SKIP_RESET:
    CALL CHECK_LED          ; Verificar si la LED debe estar encendida o apagada
    RET

CHECK_LED:
    ; Indicar configuración de HORAS/MINUTOS (Estados 1 y 2)
    CPI estado, 1        
    BREQ LED_HORA
    CPI estado, 2        
    BREQ LED_HORA

    ; Indicar configuración de FECHA (Estados 4 y 5)
    CPI estado, 4
    BREQ LED_FECHA
    CPI estado, 5
    BREQ LED_FECHA

    ; Indicar configuración de ALARMA (Estados 7 y 8)
    CPI estado, 7
    BREQ LED_ALARMA
    CPI estado, 8
    BREQ LED_ALARMA

    ; Apagar LEDs si no estamos en configuración
    CBI PORTB, PB5  ; Apagar LED de hora
    CBI PORTB, PB4  ; Apagar LED de fecha
    CBI PORTD, PD7  ; Apagar LED de alarma
    RET

LED_HORA:
    SBI PORTB, PB5  ; Encender LED de hora
    CBI PORTB, PB4  ; Apagar LED de fecha
    CBI PORTD, PD7  ; Apagar LED de alarma
    RET

LED_FECHA:
    CBI PORTB, PB5  ; Apagar LED de hora
    SBI PORTB, PB4  ; Encender LED de fecha
    CBI PORTD, PD7  ; Apagar LED de alarma
    RET

LED_ALARMA:
    CBI PORTB, PB5  ; Apagar LED de hora
    CBI PORTB, PB4  ; Apagar LED de fecha
    SBI PORTD, PD7  ; Encender LED de alarma
    RET



Cambiar_Config_Fecha:
    LDI estado, 4          ; Cambiar a 0004 (Configuración de Mes)
    CALL CHECK_LED         ; Actualizar LEDs (Encender PB4 para fecha)
    RET

Cambiar_A_Dia:
    LDI estado, 5          ; Cambiar a 0005 (Configuración de Día)
    CALL CHECK_LED         ; Asegurar que la LED se ajuste correctamente
    RET

Cambiar_A_Visualizar_Fecha:
    LDI estado, 3          ; Regresar a 0003 (Visualización de la fecha)
    CALL CHECK_LED         ; Apagar LED de fecha al volver a visualización
    RET

Cambiar_Config_Alarma:
    LDI estado, 7          ; Cambiar a 0007 (Configurar minutos de alarma)
    CALL CHECK_LED         ; Encender PD7 para alarma
    RET

Cambiar_Config_Alarma_Horas:
    LDI estado, 8          ; Cambiar a 0008 (Configurar horas de alarma)
    CALL CHECK_LED         ; Mantener PD7 encendido
    RET

Cambiar_A_Visualizar_Alarma:
    LDI estado, 6          ; Regresar a 0006 (Visualización de la alarma)
    CALL CHECK_LED         ; Apagar LED de alarma al volver a visualización
    RET

;***************************************************************************
; Función para incrementar hora, minutos, mes, día o alarma
;***************************************************************************
;***************************************************************************
; INCREMENTAR
;***************************************************************************
Incrementar:
    CPI estado, 1
    BRNE CHECK_INC_2
    RJMP Inc_Horas
CHECK_INC_2:
    CPI estado, 2
    BRNE CHECK_INC_4
    RJMP Inc_Minutos
CHECK_INC_4:
    CPI estado, 4
    BRNE CHECK_INC_5
    RJMP Inc_Mes
CHECK_INC_5:
    CPI estado, 5
    BRNE CHECK_INC_7
    RJMP Inc_Dia
CHECK_INC_7:
    CPI estado, 7
    BRNE CHECK_INC_8
    RJMP Inc_Minutos_Alarma
CHECK_INC_8:
    CPI estado, 8
    BRNE END_INC
    RJMP Inc_Horas_Alarma

END_INC:
    RET  ; Si el estado no es válido, salir
;***************************************************************************
; DECREMENTAR
;***************************************************************************
Decrementar:
    CPI estado, 1
    BRNE CHECK_DEC_2
    RJMP Dec_Horas
CHECK_DEC_2:
    CPI estado, 2
    BRNE CHECK_DEC_4
    RJMP Dec_Minutos
CHECK_DEC_4:
    CPI estado, 4
    BRNE CHECK_DEC_5
    RJMP Dec_Mes
CHECK_DEC_5:
    CPI estado, 5
    BRNE CHECK_DEC_7
    RJMP Dec_Dia
CHECK_DEC_7:
    CPI estado, 7
    BRNE CHECK_DEC_8
    RJMP Dec_Minutos_Alarma
CHECK_DEC_8:
    CPI estado, 8
    BRNE END_DEC
    RJMP Dec_Horas_Alarma

END_DEC:
    RET  ; Si el estado no es válido, salir

;***************************************************************************
; INCREMENTAR HORAS/MINUTOS (RELOJ)
;***************************************************************************
Inc_Horas:
    LDI R28, 2
    CPSE dhor, R28                ; dhor == 2 (Si no, saltar a normal incremento)
    JMP Inc_Horas_2
    LDI R28, 3
    CPSE uhor, R28                ; uhor == 4 (Esto previene errores)
    JMP Inc_Horas_2
    CLR uhor                       ; Reinicia unidades de hora
    CLR dhor                       ; Reinicia decenas de hora (00:00)
    RET

Inc_Horas_2:
    LDI R28, 9
    CPSE uhor, R28                ; uhor == 9 (Si no, solo aumenta uhor)
    JMP Inc_Horas_3
    CLR uhor                       ; Reinicia unidades de hora
    INC dhor                       ; Aumenta decenas de hora
    RET

Inc_Horas_3:
    INC uhor                       ; Aumenta unidades de hora normalmente
    RET

Inc_Minutos:
    LDI R28, 9
    CPSE umin, R28                ; umin == 9 (Si no, solo aumenta umin)
    JMP Inc_Minutos_2
    CLR umin                       ; Reinicia unidades de minutos
    JMP Inc_DMin

Inc_Minutos_2:
    INC umin                       ; Aumenta unidades de minutos normalmente
    RET

Inc_DMin:
    LDI R28, 5
    CPSE dmin, R28                ; dmin == 5 (Si no, solo aumenta dmin)
    JMP Inc_DMin_2
    CLR dmin                       ; Reinicia decenas de minutos
    JMP Inc_Horas                  ; Llamar a incremento de horas si pasa de 59

Inc_DMin_2:
    INC dmin                       ; Aumenta decenas de minutos
    RET
;***************************************************************************
; DECREMENTAR HORAS/MINUTOS (RELOJ)
;***************************************************************************
Dec_Horas:
    LDI R28, 0
    CPSE dhor, R28                ; dhor == 0 (Si no, saltar a normal decremento)
    JMP Dec_Horas_3
    LDI R28, 0
    CPSE uhor, R28                ; uhor == 0 (Si no, solo reducir uhor)
    JMP Dec_Horas_2
    LDI dhor, 2                   ; Si está en 00, cambiar a 23
    LDI uhor, 3
    RET

Dec_Horas_2:
    DEC uhor                       ; Reducir unidades de hora
    RET

Dec_Horas_3:
    LDI R28, 0
    CPSE uhor, R28                ; uhor == 0 (Si no, solo reducir uhor)
    JMP Dec_Horas_2
    LDI uhor, 9                   ; Si `uhor` es 0, cambiarlo a 9
    DEC dhor                       ; Reducir `dhor`
    RET

Dec_Minutos:
    LDI R28, 0
    CPSE umin, R28                ; umin == 0 (Si no, solo reducir umin)
    JMP Dec_Minutos_2
    LDI umin, 9                   ; Si `umin` es 0, cambiarlo a 9
    JMP Dec_DMin

Dec_Minutos_2:
    DEC umin                       ; Reducir unidades de minutos normalmente
    RET

Dec_DMin:
    LDI R28, 0
    CPSE dmin, R28                ; dmin == 0 (Si no, solo reducir dmin)
    JMP Dec_DMin_2
    LDI dmin, 5                   ; Si dmin es 0, reiniciarlo a 5
    JMP Dec_Horas                  ; Si llega a 00:00, disminuir la hora

Dec_DMin_2:
    DEC dmin                       ; Reducir decenas de minutos
    RET

;***************************************************************************
; INCREMENTAR MES (FECHA)
;***************************************************************************
Inc_Mes:
    ldi R28, 1
    ldi R29, 2
    cp mes_d, R28
    cpc mes_u, R29    ; Comparar mes_d:mes_u con 12
    brne Inc_Mes_Norm ; Si no es 12, incrementar normalmente

    ; Si es 12, reiniciar a 01
    ldi R28, 0
    mov mes_d, R28
    ldi R28, 1
    mov mes_u, R28
    ret

Inc_Mes_Norm:
    ldi R28, 9
    cp mes_u, R28
    brne Inc_Mes_IncU

    clr mes_u
    inc mes_d
    ret

Inc_Mes_IncU:
    inc mes_u
    ret

;***************************************************************************
; DECREMENTAR MES (FECHA)
;***************************************************************************
Dec_Mes:
    ldi R28, 0
    ldi R29, 1
    cp mes_d, R28
    cpc mes_u, R29    ; Comparar mes_d:mes_u con 01
    brne Dec_Mes_Norm ; Si no es 01, decrementar normalmente

    ; Si es 01, pasar a 12
    ldi R28, 1
    mov mes_d, R28
    ldi R28, 2
    mov mes_u, R28
    ret

Dec_Mes_Norm:
    ldi R28, 0
    cp mes_u, R28
    brne Dec_Mes_OnlyU

    ldi R28, 9
    mov mes_u, R28
    dec mes_d
    ret

Dec_Mes_OnlyU:
    dec mes_u
    ret
;***************************************************************************
; INCREMENTAR DIA (FECHA)
;***************************************************************************
Inc_Dia:
    CALL Obtener_Limite_Dia   ; Obtener el límite de días del mes actual en R28 y R27

    CP dia_d, R28             ; Comparar decenas con límite
    BRLO Inc_Dia_Norm         ; Si es menor, incrementar normalmente

    CP dia_u, R27             ; Comparar unidades con límite
    BRLO Inc_Dia_Norm         ; Si es menor, incrementar normalmente

    ; Si el día alcanza el límite, reiniciar a 01 y avanzar al siguiente mes
    LDI R28, 0
    MOV dia_d, R28
    LDI R28, 1
    MOV dia_u, R28
    CALL Inc_Mes              ; Avanzar al siguiente mes
    RET

Inc_Dia_Norm:
    LDI R28, 9
    CPSE dia_u, R28           ; Unidades == 9
    RJMP Inc_Dia_U            ; Si no, solo incrementar unidades

    CLR dia_u                 ; Reiniciar unidades a 0
    INC dia_d                 ; Incrementar decenas
    RET

Inc_Dia_U:
    INC dia_u                 ; Incrementar unidades de día
    RET
;***************************************************************************
; DECREMENTAR DIA (FECHA)
;***************************************************************************
Dec_Dia:
    LDI R28, 0
    CPSE dia_d, R28   ; Si dia_d ? 0, continuar
    RJMP Dec_Dia_Norm

    CPSE dia_u, R28   ; Si dia_u ? 0, continuar
    RJMP Dec_Dia_Norm

    ; Si el día es 01, pasar al último día del mes anterior
    CALL Dec_Mes       ; Retroceder un mes
    CALL Obtener_Limite_Dia  ; Obtener límite del mes anterior

    MOV dia_d, R28    ; Cargar decenas del último día
    MOV dia_u, R27    ; Cargar unidades del último día
    RET

Dec_Dia_Norm:
    LDI R28, 0
    CPSE dia_u, R28   ; Si dia_u ? 0, continuar
    RJMP Dec_Dia_U

    LDI R28, 9
    MOV dia_u, R28
    DEC dia_d         ; Reducir decenas de día
    RET

Dec_Dia_U:
    DEC dia_u         ; Reducir unidades de día normalmente
    RET

;***************************************************************************
; FUNCION PARA VERIFICAR EL LIMITE DE DIAS SEGUN EL MES ACTUAL (FECHA)
;***************************************************************************
Verificar_Limite_Dia:
    call Obtener_Limite_Dia

    cp dia_d, R28
    brlo Dia_Valido

    cp dia_u, R27
    brlo Dia_Valido

    ; Si supera el límite, pasar a 01 y avanzar de mes
    ldi R28, 0
    mov dia_d, R28
    ldi R28, 1
    mov dia_u, R28
    call Inc_Mes
    ret

Dia_Valido:
    ret

;***************************************************************************
;FUNCION PARA OBTENER EL NUMERO DE DIAS DEL MES ACTUAL
;***************************************************************************
Obtener_Limite_Dia:
    ; Verificar si el mes es FEBRERO (28 días)
    LDI R28, 0
    CP mes_d, R28
    BRNE NoFebrero
    LDI R28, 2
    CP mes_u, R28
    BRNE NoFebrero
    LDI R28, 2  ; Decenas = 2
    LDI R27, 8  ; Unidades = 8  (28 días)
    RET

NoFebrero:
    ; Verificar si el mes tiene 30 días (Abril, Junio, Septiembre, Noviembre)
    LDI R28, 0
    CP mes_d, R28
    BRNE NoMes30
    LDI R28, 4  ; Abril (04)
    CP mes_u, R28
    BREQ Mes30
    LDI R28, 6  ; Junio (06)
    CP mes_u, R28
    BREQ Mes30
    LDI R28, 9  ; Septiembre (09)
    CP mes_u, R28
    BREQ Mes30

    LDI R28, 1
    CP mes_d, R28
    BRNE NoMes30
    LDI R28, 1  ; Noviembre (11)
    CP mes_u, R28
    BREQ Mes30

NoMes30:
    ;  Si no es Febrero ni un mes de 30 días, entonces tiene 31 días
    LDI R28, 3  ; Decenas = 3
    LDI R27, 1  ; Unidades = 1 (31 días)
    RET

Mes30:
    ; ?? Si el mes es 04, 06, 09 o 11, asignar 30 días
    LDI R28, 3  ; Decenas = 3
    LDI R27, 0  ; Unidades = 0 (30 días)
    RET


;***************************************************************************
;INCREMENTAR MINUTOS DE LA ALARMA
;***************************************************************************
Inc_Minutos_Alarma:
    MOV R28, alar_min_u          
    CPI R28, 9                   
    BRNE Inc_Min_Alarma_OnlyU    

    ; Si `alar_min_u` == 9, resetear y aumentar `alar_min_d`
    CLR alar_min_u               
    INC alar_min_d               

    MOV R28, alar_min_d          
    CPI R28, 6                  
    BRNE RET_INC_MIN_ALARMA      

    ; Si `alar_min_d` == 6, reiniciar a 00 y aumentar la hora
    CLR alar_min_d               
    RJMP Inc_Horas_Alarma        

RET_INC_MIN_ALARMA:
    RET

Inc_Min_Alarma_OnlyU:
    INC alar_min_u              
    RET
;***************************************************************************
;DECREMENTAR MINUTOS DE LA ALARMA
;***************************************************************************
Dec_Minutos_Alarma:
    MOV R28, alar_min_u         
    CPI R28, 0                  
    BRNE Dec_Min_Alarma_OnlyU    

    ; Si alar_min_u == 0, setear a 9 y decrementar alar_min_d
    LDI R28, 9
    MOV alar_min_u, R28          
    DEC alar_min_d               

    MOV R28, alar_min_d         
    CPI R28, 255                 
    BRNE RET_DEC_MIN_ALARMA      

    ; Si alar_min_d es -1 (255 en binario), setear a 5 y decrementar hora
    LDI R28, 5
    MOV alar_min_d, R28          
    RJMP Dec_Horas_Alarma        

RET_DEC_MIN_ALARMA:
    RET

Dec_Min_Alarma_OnlyU:
    DEC alar_min_u              
    RET

;***************************************************************************
; INCREMENTAR HORAS DE LA ALARMA
;***************************************************************************
Inc_Horas_Alarma:
    MOV R28, alar_hor_d          ; Copiar decenas de horas
    CPI R28, 2                   ; Decenas de hora == 2
    BRNE Inc_Horas_Alarma_2

    MOV R28, alar_hor_u          ; Copiar unidades de horas
    CPI R28, 3                   ; Unidades de hora == 3 (para 23  00)
    BRNE Inc_Horas_Alarma_2

    CLR alar_hor_u               ; Reiniciar unidades de hora a 0
    CLR alar_hor_d               ; Reiniciar decenas de hora a 0
    RET

Inc_Horas_Alarma_2:
    MOV R28, alar_hor_u          ; Copiar unidades de horas
    CPI R28, 9                   ; ¿Unidades de hora == 9?
    BRNE Inc_Horas_Alarma_3

    CLR alar_hor_u               ; Reiniciar unidades a 0
    INC alar_hor_d               ; Incrementar decenas
    RET

Inc_Horas_Alarma_3:
    INC alar_hor_u               ; Incrementar unidades de hora
    RET

;***************************************************************************
; DECREMENTAR HORAS DE LA ALARMA
;***************************************************************************
Dec_Horas_Alarma:
    MOV R28, alar_hor_d          ; Copiar decenas de horas
    CPI R28, 0                   ; Decenas de hora == 0
    BRNE Dec_Horas_Alarma_2

    MOV R28, alar_hor_u          ; Copiar unidades de horas
    CPI R28, 0                   ; Unidades de hora == 0
    BRNE Dec_Horas_Alarma_2

    LDI R28, 2
    MOV alar_hor_d, R28          ; Reiniciar decenas a 2
    LDI R28, 3
    MOV alar_hor_u, R28          ; Reiniciar unidades a 3 (00  23)
    RET

Dec_Horas_Alarma_2:
    MOV R28, alar_hor_u          ; Copiar unidades de horas
    CPI R28, 0                   ; Unidades de hora == 0
    BRNE Dec_Horas_Alarma_3

    LDI R28, 9
    MOV alar_hor_u, R28          ; Reiniciar unidades a 9
    DEC alar_hor_d               ; Decrementar decenas
    RET

Dec_Horas_Alarma_3:
    DEC alar_hor_u               ; Decrementar unidades normalmente
    RET

;***************************************************************************
; Inicializar Timer0 para generar interrupciones cada 10ms
;***************************************************************************
Init_T0:
    LDI R16, (1 << CS02) | (1 << CS00) ; Prescaler 1024
    OUT TCCR0B, R16
    LDI R16, 99
    OUT TCNT0, R16
    LDI R16, (1 << TOIE0)
    STS TIMSK0, R16
    RET

;***************************************************************************
; Interrupción Timer0 Overflow (Cuenta segundos y verifica la alarma)
;***************************************************************************
ISR_TIMER0_OVF:
    LDI R17, 99
    OUT TCNT0, R17
    SBI TIFR0, TOV0

;-------------------------------------
; INCREMENTAR SEGUNDOS Y MINUTOS
;-------------------------------------
    INC cont1s
    CPI cont1s, 100    
    BRNE CHECK_500MS
    CLR cont1s       

    INC cont60s        
    CPI cont60s, 60    
    BRNE CHECK_500MS
    CLR cont60s        

    CALL Inc_Minutos  

;-------------------------------------
; VERIFICAR SI SON LAS 00:00
;-------------------------------------
    LDI R28, 0
    CP dhor, R28  
    BRNE CHECK_ALARM
    CP uhor, R28  
    BRNE CHECK_ALARM
    CP dmin, R28  
    BRNE CHECK_ALARM
    CP umin, R28  
    BRNE CHECK_ALARM

    CALL Inc_Dia  ;  Incrementar día si la hora es 00:00

;-------------------------------------
; VERIFICAR SI DEBE SONAR LA ALARMA
;-------------------------------------
CHECK_ALARM:
    SBIC PORTC, PC5  ;  Si el buzzer ya está encendido, evitar repetir
    RJMP CHECK_500MS

    ; Comparar la hora actual con la alarma
    CP dhor, alar_hor_d  
    BRNE CHECK_500MS
    CP uhor, alar_hor_u  
    BRNE CHECK_500MS
    CP dmin, alar_min_d  
    BRNE CHECK_500MS
    CP umin, alar_min_u  
    BRNE CHECK_500MS

    ; Si la hora coincide con la alarma, activar alarma_activa
    LDI R28, 1
    MOV alarma_activa, R28  ; ENCENDER ALARMA

CHECK_500MS:
    INC cont500ms    
    CPI cont500ms, 50
    BRNE END_ISR
    CLR cont500ms
    SBI PINC, PC4  ; Parpadeo de los dos puntos

    ; Si alarma_activa está encendida, hacer sonar el buzzer sin bloquear el programa
    TST alarma_activa  ; Verificar si alarma está activa
    BREQ END_ISR       ; Si está en 0, no hacer nada
    SBIC PORTC, PC5    ; Si el buzzer está encendido, apagarlo
    RJMP APAGAR_BUZZER

ENCENDER_BUZZER:
    SBI PORTC, PC5  ; ENCENDER BUZZER
    RJMP END_ISR

APAGAR_BUZZER:
    CBI PORTC, PC5  ; APAGAR BUZZER
    RJMP END_ISR

END_ISR:
    RETI

;***************************************************************************
; DISPLAYS DE LOS ESTADOS
;***************************************************************************

;***************************************************************************
; DHOR_DISPLAY (Decenas de Horas)
;***************************************************************************
DHOR_DISPLAY:
    CBI PORTB, PB0
    CBI PORTB, PB1
    CBI PORTB, PB2
    CBI PORTB, PB3

    MOV R27, dhor
    LDI ZH, HIGH(T7S << 1)
    LDI ZL, LOW(T7S << 1)
    ADD ZL, R27
    LPM R27, Z

    IN R28, PORTD   ; Leer el estado actual de PORTD
    ANDI R28, 0b10000000  ; Conservar solo PD7
    OR R27, R28  ; Fusionar el display con PD7
    OUT PORTD, R27  

    SBI PORTB, PB0  
    RET

;***************************************************************************
; UHOR_DISPLAY (Unidades de Horas)
;***************************************************************************
UHOR_DISPLAY:
    CBI PORTB, PB0
    CBI PORTB, PB1
    CBI PORTB, PB2
    CBI PORTB, PB3

    MOV R27, uhor
    LDI ZH, HIGH(T7S << 1)
    LDI ZL, LOW(T7S << 1)
    ADD ZL, R27
    LPM R27, Z

    IN R28, PORTD
    ANDI R28, 0b10000000  
    OR R27, R28  
    OUT PORTD, R27  

    SBI PORTB, PB1  
    RET

;***************************************************************************
; DMIN_DISPLAY (Decenas de Minutos)
;***************************************************************************
DMIN_DISPLAY:
    CBI PORTB, PB0
    CBI PORTB, PB1
    CBI PORTB, PB2
    CBI PORTB, PB3

    MOV R27, dmin
    LDI ZH, HIGH(T7S << 1)
    LDI ZL, LOW(T7S << 1)
    ADD ZL, R27
    LPM R27, Z

    IN R28, PORTD
    ANDI R28, 0b10000000  
    OR R27, R28  
    OUT PORTD, R27  

    SBI PORTB, PB2  
    RET

;***************************************************************************
; UMIN_DISPLAY (Unidades de Minutos)
;***************************************************************************
UMIN_DISPLAY:
    CBI PORTB, PB0
    CBI PORTB, PB1
    CBI PORTB, PB2
    CBI PORTB, PB3

    MOV R27, umin
    LDI ZH, HIGH(T7S << 1)
    LDI ZL, LOW(T7S << 1)
    ADD ZL, R27
    LPM R27, Z

    IN R28, PORTD
    ANDI R28, 0b10000000  
    OR R27, R28  
    OUT PORTD, R27  

    SBI PORTB, PB3  
    RET

;***************************************************************************
; DDIA_DISPLAY (Decenas de Día)
;***************************************************************************
DDIA_DISPLAY:
    CBI PORTB, PB0
    CBI PORTB, PB1
    CBI PORTB, PB2
    CBI PORTB, PB3

    MOV R27, dia_d
    LDI ZH, HIGH(T7S << 1)
    LDI ZL, LOW(T7S << 1)
    ADD ZL, R27
    LPM R27, Z

    IN R28, PORTD
    ANDI R28, 0b10000000  
    OR R27, R28  
    OUT PORTD, R27  

    SBI PORTB, PB0  
    RET

;***************************************************************************
; UDIA_DISPLAY (Unidades de Día)
;***************************************************************************
UDIA_DISPLAY:
    CBI PORTB, PB0
    CBI PORTB, PB1
    CBI PORTB, PB2
    CBI PORTB, PB3

    MOV R27, dia_u
    LDI ZH, HIGH(T7S << 1)
    LDI ZL, LOW(T7S << 1)
    ADD ZL, R27
    LPM R27, Z

    IN R28, PORTD
    ANDI R28, 0b10000000  
    OR R27, R28  
    OUT PORTD, R27  

    SBI PORTB, PB1  
    RET

;***************************************************************************
; DMES_DISPLAY (Decenas de Mes)
;***************************************************************************
DMES_DISPLAY:
    CBI PORTB, PB0
    CBI PORTB, PB1
    CBI PORTB, PB2
    CBI PORTB, PB3

    MOV R27, mes_d
    LDI ZH, HIGH(T7S << 1)
    LDI ZL, LOW(T7S << 1)
    ADD ZL, R27
    LPM R27, Z

    IN R28, PORTD
    ANDI R28, 0b10000000  
    OR R27, R28  
    OUT PORTD, R27  

    SBI PORTB, PB2  
    RET

;***************************************************************************
; UMES_DISPLAY (Unidades de Mes)
;***************************************************************************
UMES_DISPLAY:
    CBI PORTB, PB0
    CBI PORTB, PB1
    CBI PORTB, PB2
    CBI PORTB, PB3

    MOV R27, mes_u
    LDI ZH, HIGH(T7S << 1)
    LDI ZL, LOW(T7S << 1)
    ADD ZL, R27
    LPM R27, Z

    IN R28, PORTD
    ANDI R28, 0b10000000  
    OR R27, R28  
    OUT PORTD, R27  

    SBI PORTB, PB3  
    RET

;***************************************************************************
; DHOR_ALARM_DISPLAY (Decenas de Horas de la Alarma)
;***************************************************************************
DHOR_ALARM_DISPLAY:
    CBI PORTB, PB0
    CBI PORTB, PB1
    CBI PORTB, PB2
    CBI PORTB, PB3

    MOV R27, alar_hor_d
    LDI ZH, HIGH(T7S << 1)
    LDI ZL, LOW(T7S << 1)
    ADD ZL, R27
    LPM R27, Z

    IN R28, PORTD
    ANDI R28, 0b10000000  
    OR R27, R28  
    OUT PORTD, R27  

    SBI PORTB, PB0  
    RET

;***************************************************************************
; UHOR_ALARM_DISPLAY (Unidades de Horas de la Alarma)
;***************************************************************************
UHOR_ALARM_DISPLAY:
    CBI PORTB, PB0
    CBI PORTB, PB1
    CBI PORTB, PB2
    CBI PORTB, PB3

    MOV R27, alar_hor_u
    LDI ZH, HIGH(T7S << 1)
    LDI ZL, LOW(T7S << 1)
    ADD ZL, R27
    LPM R27, Z

    IN R28, PORTD
    ANDI R28, 0b10000000  
    OR R27, R28  
    OUT PORTD, R27  

    SBI PORTB, PB1  
    RET

UMIN_ALARM_DISPLAY:
    CBI PORTB, PB0
    CBI PORTB, PB1
    CBI PORTB, PB2
    CBI PORTB, PB3

    MOV R27, alar_min_u  ; Unidades de minutos de la alarma
    LDI ZH, HIGH(T7S << 1)
    LDI ZL, LOW(T7S << 1)
    ADD ZL, R27
    LPM R27, Z   ; Cargar el valor del display en R27

    IN R28, PORTD  ; Leer el estado actual de PORTD
    ANDI R28, 0b10000000  ; Conservar solo PD7
    OR R27, R28  ; Combinar el valor del display con PD7
    OUT PORTD, R27  ; Enviar al puerto

    SBI PORTB, PB3  ; Activar el dígito del display
    RET

;***************************************************************************
; DMIN_ALARM_DISPLAY (Decenas de Minutos de la Alarma)
;***************************************************************************
DMIN_ALARM_DISPLAY:
    CBI PORTB, PB0
    CBI PORTB, PB1
    CBI PORTB, PB2
    CBI PORTB, PB3

    MOV R27, alar_min_d  ; Decenas de minutos de la alarma
    LDI ZH, HIGH(T7S << 1)
    LDI ZL, LOW(T7S << 1)
    ADD ZL, R27
    LPM R27, Z

    IN R28, PORTD         ; Leer el estado actual de PORTD
    ANDI R28, 0b10000000  ; Conservar solo PD7
    OR R27, R28           ; Fusionar el display con PD7
    OUT PORTD, R27  

    SBI PORTB, PB2  
    RET
