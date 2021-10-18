%% Proyecto: THD - AE N9320A - MEII 
% Implementacion de TDH en el analizador de espectro Agilent
% N9320A mediante Matlab.
% Versión 1.5

% Limpieza de workspace y consola
clear all;
clc;

% Variables utilizadas para la medicion y calculos
NTHR = -80;
cantArmonicas = 10;
A = double(zeros(1,cantArmonicas));
Amplitude = double(zeros(1,cantArmonicas));
F = double(zeros(1,cantArmonicas));
Anoise = double(0);
FoundFlag = 0;
MinSpanFlag = 0;
SetSpanBuffer = 'SENS:FREQ:SPAN';
SetStartBuffer = 'SENS:FREQ:STAR';
SetStopBuffer = 'SENS:FREQ:STOP';
SetCentBuffer = 'SENS:FREQ:CENT';

% Instanciacion del objeto que prepara la comunicacion
instrObj = visa('NI', 'USB0::0x0957::0x2118::0163000547::0::INSTR');

% Abrimos la comunicacion mediante el objeto
fopen(instrObj);

%if instrObj.Status ~= open
    % Desconectar y avisar
      
% Reseteamos el dispositivo mediante *RST : reset.
% Limpieza de registro con *CLS : clear status register.
fprintf(instrObj, '*RST\n')
%fprintf(instrObj, '*CLS \n')
% Esperamos para el reset.
pause(5);

% Le pedimos al dispositivo que envie la informacion del equipo
InfoBuffer = query(instrObj, '*IDN?');

% Configuracion para que registre errores por comando y query
fprintf(instrObj, '*ESE 36');
% Consulta por la correcta configuracion de lo antedicho
ErrorBuffer = query(instrObj, '*ESE?');
if strcmp(ErrorBuffer, '36') 
    ErrorFlag = UP;
else
    fprintf('No pudo configurarse el registro de error.\n');
end

% Axis-Y en dBm
fprintf(instrObj, 'UNIT:POW DBM\n');

% Start frequency - no necesario
fprintf(instrObj, 'SENS:FREQ:STAR 0');

% Stop frequency - no necesario
fprintf(instrObj, 'SENS:FREQ:STOP 1e9');

% Habilitacion del uso de threshold
fprintf(instrObj, 'CALC:MARK:PEAK:THR:STATE 1\n');

% Consulta por estado de threshold al equipo
ans = query(instrObj, 'CALC:MARK:PEAK:THR:STATE?');
if ans == '1'
    fprintf('Threshold activado.\n')
else
    fprintf('Fallo la habilitación de threshold.\n');
end

% Configuracion de threshold para la medicion de THD;
% valor en dBm.
fprintf(instrObj, 'CALC:MARK:PEAK:THR -50 \n')

% Configuracion del valor de atenuacion para la medicion
ans = query(instrObj, 'SENS:POW:RF:ATT?');
if ans ~= '20'
    fprintf(instrObj, 'SENS:POW:RF:ATT 20');
end

% Conectada la fuente que se desee conocer su THD,
% se procede a la medición de sus armonicas.

%------------------------------------------------------------------*/
% Que pasa si no hay señal conectada, en este caso habria que pensar
% una respuesta.....
% Falta saber que devuelve el equipo cuando no hay nada arriba del 
% umbral!
%------------------------------------------------------------------*/


% Algoritmo de busqueda de portadora.
while ~FoundFlag
    fprintf(instrObj, 'CALC:MARK:MAX \n');
    ErrorBuffer = query(instrObj, 'SYST:ERR?');
    
    %  Si la frecuencia es menor al 1Mhz hay que realizar el proximo loop
    % 1) Peak search max
    % 2) Peak > -50 dBm ?
    % 3) Stop Frequency decrementa logaritmicamente.
    % Modificar el ActualSpanStr
    if ~strcmp(ErrorBuffer, '780NoPeakFound')
        % No hubo error -> Se encontro un pico.
        fprintf(instrObj, 'CALC:MARK:SET:CENT \n');
        ActualSpanStr = query(instrObj, 'SENS:FREQ:SPAN?');
        % Buscar forma de que me deje el ActualSpan como %.02e
        % ActualSpan = num2str(ActualSpanStr, '%.01e');
        i = 0;
        while ~MinSpanFlag
            AuxStr = num2str(ActualSpan / power(10, i), '%.01e');
            if strcmp(AuxStr, '1.0e+05');
                % RBW = 10kHz ?
                MinSpanFlag = 1;
            end
            AuxStr = cat(2,AuxStr,'\n');
            fprintf(instrObj, strjoin({SetSpanBuffer, AuxStr}));   
            fprintf(instrObj, 'CALC:MARK:MAX \n');
            AuxFreq = query(instrObj, 'CALC:MARK:X?');
            F(1) = str2double(AuxFreq);
            if F(1) < 0
                fprintf(instrObj, 'CALC:MARK:MAX:RIGHT \n');
            end
            fprintf(instrObj, 'CALC:MARK:SET:CENT \n');
            i = i + 1;
        end
        AuxAmplitude = query(instrObj, 'CALC:MARK:Y?');
        A(1) = str2double(AuxAmplitude);
        Amplitude(1) = power(10, (A(1)/10)) * 1e-3;
        
        if A(1) > NTHR
            % Cuando encontro la fundamental, obtengo su frecuencia.
            AuxFreq = query(instrObj, 'CALC:MARK:X?');
            F(1) = str2double(AuxFreq);
            % Indicar frecuencia de la portadora en la GUI !
            fprintf(instrObj, 'CALC:MARK:SET:RLEV \n'); 
            % Trasformamos los dBm obtenidos de la portadora:
            % A(1) = power(10, (A(1)/10)) * 1e-3;
            % Habilitamos el uso de delta markers para medir diferencias:
            % fprintf(instrObj, 'CALC:MARK:MODE DELT\n');
            FoundFlag = 1;
        else
            A(1) = 0;   % Se leyo ruido. Se debe indicar en la GUI ! 
                           % Puede haber fallado el algoritmo de busqueda,
                           % o bien, el usuario nunca conecto el generador.
        end
    else
        % Hubo error '780NoPeakFound' -> No se encontro armonico
        % fundamental en el SPAN completo, por lo tanto debe indicar nivel
        % muy bajo o bien disminuir el Threshold.
        FoundFlag = 0;
    end
end


% Algoritmo de medicion de armonicos de la fundamental. Situa los armonicos
% en ventanas a partir de la frecuencia esperada del armonico F(i-1)*2.
for i = 2 : cantArmonicas
    % Movemos el analizador a la proxima ventana manteniendo el mismo SPAN.
    AuxCent =  num2str(F(1)*i);
    
    % Center frequency -> a la proxima armonica
    fprintf(instrObj, strjoin({SetCentBuffer, AuxCent}));
    
    fprintf(instrObj, 'CALC:MARK:MAX \n');
    ErrorBuffer = query(instrObj, 'SYST:ERR?');
    
    if ~strcmp(ErrorBuffer, '780NoPeakFound')
        % No hubo error -> Se encontro la proxima armonica.
        fprintf(instrObj, 'CALC:MARK:SET:CENT \n');
        fprintf(instrObj, 'CALC:MARK:MAX \n');
        AuxAmplitude = query(instrObj, 'CALC:MARK:Y?');
        A(i) = str2double(AuxAmplitude);
        % Trasformamos los dBm obtenidos de la portadora:
        Amplitude(i) = power(10, (A(i)/10)) * 1e-3;
        AuxFreq = query(instrObj, 'CALC:MARK:X?');
        F(i) = str2double(AuxFreq);
    else
        % Hubo error '780NoPeakFound' -> No se encontro el proximo
        % armonico. Se le debe asignar el valor de threshold. REVISAR.
        A(i) = NTHR;
        Amplitude(i) = power(10, (A(i)/10)) * 1e-3;
    end
end

% No se modifico nada desde 1.4 a 1.5
% Algoritmo de medicion de ruido. Avisar que no haya generador conectado !
% Falta revision, es necesario calcularlo con un algoritmo mas robusto.
fprintf(instrObj, 'CALC:MARK:MAX \n');
AuxAmplitude = query(instrObj, 'CALC:MARK:Y?');
Anoise = str2double(AuxAmplitude);
Anoise = power(10,(Anoise/10)) * 1e-3;

%% Calculo de THD

% Falta completar. A continuacion, los armonicos A(i)
% deben estar en 'veces' y elevados al cuadrado.
Amplitude = power(Amplitude, 2);
THD = sqrt(sum(Amplitude(2:cantArmonicas)))/Amplitude(1)*100;
% Tambien puede resolverse por diferencias relativas usando delta markers.
% En este caso, A(1) tendria el valor del armonico fundamental -> se indica
% en GUI. Y el resto serian las diferencias relativas A(2) = A(2)/A(1).
% Falta revisar cual es la mejor opcion.
THD = sqrt(sum(A(2:cantArmonicas)))*100;

% THD+N contempla la amplitud de ruido. REVISAR.
THDN = THD + (Anoise/A(1));
% O bien, considerando diferencias relativas.
THDN = sqrt(sum(A(2:cantArmonicas)) + (Anoise-A(1)))*100;

% Cierre de la comunicacion con el equipo
fclose(instrObj);
instrreset
clear instrObj
clear ans

% ###### END OF FILE ######

% Otros comandos

% Configuración de promediado para disminuir el cesped
% fprintf(instrObj, 'SENS:AVER:STAT ON \n');
% fprintf(instrObj, 'SENS:AVER:COUN 5 \n');

% Consulta por si hubo error recientemente
% fprintf(instrObj, 'SYST:ERR? \n');

% Center frequency - no necesario
% fprintf(instrObj, 'SENS:FREQ:CENT 50e6');
   
% Single sweep mode - 
% fprintf(instrObj, 'INIT:CONT 0\n');

% Definición de la excursión de marcador. Minima excursión de señal sobre
% el threshold para que sea reconocida por la rutina de Peak Search
% fprintf(instrObj, 'CALC:MARK:PEAK:EXC -45 \n');
% ans = query(instrObj, 'CALC:MARK:PEAK:EXC?');
