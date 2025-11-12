# Tp-final-ED2
-----------------------------
Profesor del práctico Marcos Javier Blasco, Electrónica Digital 2, año 2025.

Grupo 4: Potinski Mijail Andrés, Concodi Carlos Javier, Sorbera Josué Emanuel

Trabajo práctico final, proyecto Voltímetro-Osciloscopio con Pic16f887

Idea: utilizar el adc del pic para medir un voltaje y mostrarlo en 3 displays, y usando la conexion serial
muestrear una señal en la computadora usando un programa en python.


--------------------------
### Lista de componentes:
pic16f887

3x displays 7 segmentos cátodo comun FYS-5211-AG

cristal de 4Mhz

2x capacitores ceramicos 22nF

resistencias de 1k y 10k

botón

perfboard

terminal atornillada

adaptador usb a ttl 

------------------------

## Esquemático
<img width="1409" height="708" alt="image" src="https://github.com/user-attachments/assets/0ba2c94a-0ad9-40d4-9cf8-03dc10d36f10" />

## Programa
muestreando una señal senoidal de 1hz
<img width="2560" height="1034" alt="1hz" src="https://github.com/user-attachments/assets/15b328b4-54b4-4e3f-bd1e-836b51ee6b46" />

## Board
![Imagen de WhatsApp 2025-11-12 a las 15 31 38_594f5b9c](https://github.com/user-attachments/assets/339b00b3-582d-424f-9a9e-6991144a5e4c)
![Imagen de WhatsApp 2025-11-12 a las 15 31 39_3f975555](https://github.com/user-attachments/assets/1691bd16-478d-4508-a62b-9b5e129493a6)

## Carcasa
<img width="1522" height="759" alt="image" src="https://github.com/user-attachments/assets/6d3252b7-9e14-4e35-bb37-a8e8a09f5929" />

## Mediciones
Según las pruebas podemos muestrear hasta señales de 150Hz sin perder tanta resolucion de manera práctica. Obtenemos en promedio un error de medición de 16% en la frecuencia y 5% en voltaje comparado a un osciloscopio UTD2102CEX+ usando una fuente regulada y una generador de señales XR2206 con un divisor resistivo para estar en el rango de 0-5v que acepta el pic.

<img width="1104" height="682" alt="Medición de frecuencia " src="https://github.com/user-attachments/assets/57c018d8-fdd3-4161-bc1a-2f2cdfe2c968" />
<img width="1104" height="682" alt="Medición de voltaje medio" src="https://github.com/user-attachments/assets/edc4a743-f881-40b0-97af-7ce8d637aa41" />




