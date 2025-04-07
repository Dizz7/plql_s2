-- USUARIO EA1_2_MDY_FOL

/* Se modificó la contraseña del usuario de EA1_2-CreaUsuario.sql por 
   requerimiento de seguridad de Oracle SQL Developer (contraseña 'duoc')

   La línea alterada fue esta: 

   CREATE USER EA1_2_MDY_FOL IDENTIFIED BY "H0l4.O_r4cL3!"
	
*/


-- PROCEDIMIENTO ALMACENADO 1

/* Procedimiento almacenado para retornar
   la cantidad de atenciones de un médico
   según el RUT del médico y el periodo 
   ingresado. */


CREATE OR REPLACE PROCEDURE sp_total_aten_med (
    p_run_med NUMBER, 
    p_periodo VARCHAR2, 
    p_total_atenciones OUT NUMBER
) 
IS
BEGIN
    SELECT NVL(COUNT(ate_id), 0)
    INTO p_total_atenciones
    FROM atencion
    WHERE TO_CHAR(fecha_atencion, 'MM-YYYY') = p_periodo
    AND med_run = p_run_med;
END sp_total_aten_med;
/





-- FUNCIÓN ALMACENADA 1

/* Función almacenada para calcular el promedio 
   de los sueldos de los médicos según el ID 
   de un cargo ingresado. */

CREATE OR REPLACE FUNCTION fn_prom_sueldos_cargo
 (p_id_cargo NUMBER)
	RETURN NUMBER
IS
    promedio_sueldo NUMBER;
BEGIN

    SELECT 
        NVL(AVG (sueldo_base), 0)
    INTO promedio_sueldo
    FROM medico
    WHERE car_id = p_id_cargo;
    
    RETURN promedio_sueldo;
END fn_prom_sueldos_cargo;
/





-- FUNCIÓN ALMACENADA 2

/* Función almacenada para calcular el costo 
   total de atenciones de un medico en un periodo 
   MM-YYYY */

CREATE OR REPLACE FUNCTION fn_costo_atenciones_med (
    p_med_run  NUMBER,
    p_periodo  VARCHAR2) 
RETURN NUMBER
IS
    costo_atenciones_med NUMBER;
    v_inicio_mes DATE;
    v_fin_mes DATE;

BEGIN
    -- Definir el inicio y fin del mes según el periodo
    v_inicio_mes := TO_DATE('01-' || p_periodo, 'DD-MM-YYYY');
    v_fin_mes := LAST_DAY(v_inicio_mes);

    -- Obtener el costo de las atenciones del médico en el período
    SELECT 
        NVL(SUM(costo), 0)
    INTO costo_atenciones_med
    FROM atencion
    WHERE med_run = p_med_run
    AND fecha_atencion BETWEEN v_inicio_mes AND v_fin_mes;

    -- Retornar el costo total de las atenciones
    RETURN costo_atenciones_med;
END fn_costo_atenciones_med;
/







-- PROCEDIMIENTO ALMACENADO 2 (PRINCIPAL)

/* Procedimiento almacenado para generar
   ambos informes solicitados ingresando
   el ID de una unidad y un periodo 
   periodo MM-YYYY. */


CREATE OR REPLACE PROCEDURE sp_generar_informes (
    p_id_unidad NUMBER,
    p_periodo   VARCHAR2) 
IS
    -- Cursor explícito para obtener los médicos de la unidad
    CURSOR cr_medicos IS 
        SELECT 
            m.med_run || '-' || m.dv_run AS RUT_MEDICO,
            m.med_run,
            INITCAP(m.apaterno || ' ' || m.amaterno || ' ' || m.pnombre || ' ' || NVL(m.snombre, '')) AS nombre_completo, 
            m.sueldo_base, 
            c.nombre AS cargo_nombre, 
            u.nombre AS unidad_nombre, 
            m.car_id
        FROM medico m
        JOIN cargo c ON m.car_id = c.car_id
        JOIN unidad u ON m.uni_id = u.uni_id
        WHERE m.uni_id = p_id_unidad;
        
    -- Variables para almacenar datos del cursor
    v_rut_medico        VARCHAR2(12);
    v_rut_sin_dv        MEDICO.med_run%TYPE;
    v_nombre_completo   VARCHAR2(50);
    v_sueldo_base       MEDICO.sueldo_base%TYPE;
    v_nombre_cargo      CARGO.nombre%TYPE;
    v_nombre_unidad     UNIDAD.nombre%TYPE;
    v_car_id            MEDICO.car_id%TYPE;

    -- Variables para cálculos
    v_total_atenciones NUMBER;
    v_costo_atenciones_med NUMBER;
    v_costo_atenciones NUMBER;
    v_tasa_aporte      NUMBER;
    v_promedio_sueldo  NUMBER;
    v_diferencia_cargo NUMBER;
    v_sobre_promedio   VARCHAR2(2); 
    v_total_costo_atenciones NUMBER;
    
BEGIN
    -- Borrado de tablas DETALLE_ATENCIONES y RESUMEN_MEDICO
    EXECUTE IMMEDIATE 'TRUNCATE TABLE DETALLE_ATENCIONES';
    EXECUTE IMMEDIATE 'TRUNCATE TABLE RESUMEN_MEDICO';

    -- Abrir el cursor explícito
    OPEN cr_medicos;
    
    LOOP 
        -- Obtener la siguiente fila del cursor
        FETCH cr_medicos INTO v_rut_medico, v_rut_sin_dv, v_nombre_completo, v_sueldo_base, v_nombre_cargo, v_nombre_unidad, v_car_id;
        EXIT WHEN cr_medicos%NOTFOUND;

        -- Obtener el total de atenciones del médico
        sp_total_aten_med(v_rut_sin_dv, p_periodo, v_total_atenciones);

        -- Obtener el costo total de atenciones del médico
        v_costo_atenciones_med := fn_costo_atenciones_med(v_rut_sin_dv, p_periodo);

       -- Cursor implícito para obtener el costo total de atenciones
        SELECT 
            NVL(SUM(a.costo), 0)
        INTO v_total_costo_atenciones
        FROM atencion a
        JOIN medico m ON a.med_run = m.med_run
        JOIN cargo c ON m.car_id = c.car_id
        JOIN unidad u ON m.uni_id = u.uni_id
        WHERE TO_CHAR(a.fecha_atencion, 'MM-YYYY') = p_periodo 
        AND m.uni_id = p_id_unidad;

       -- Calcular la tasa de aporte para el médico
        IF v_total_costo_atenciones > 0 THEN
            IF v_costo_atenciones_med > 0 THEN
                v_tasa_aporte := v_costo_atenciones_med / v_total_costo_atenciones;
            ELSE
                v_tasa_aporte := 0;
            END IF;
        ELSE
            v_tasa_aporte := 0;
        END IF;

        -- Insertar en tabla DETALLE_ATENCIONES
        INSERT INTO DETALLE_ATENCIONES (rut_medico, periodo, total_atenciones, costo_atenciones, tasa_aporte_periodo)
        VALUES (v_rut_medico, p_periodo, v_total_atenciones, v_costo_atenciones_med, v_tasa_aporte);

        -- Obtener promedio de sueldos del cargo
        v_promedio_sueldo := fn_prom_sueldos_cargo(v_car_id);

        -- Calcular diferencia de sueldo
        v_diferencia_cargo := ROUND(ABS(v_sueldo_base - v_promedio_sueldo));

        -- Determinar si está sobre el promedio
        IF v_sueldo_base >= v_promedio_sueldo THEN
            v_sobre_promedio := 'SI';
        ELSE
            v_sobre_promedio := 'NO';
        END IF;

        -- Insertar en tabla RESUMEN_MEDICO
        INSERT INTO RESUMEN_MEDICO (rut_medico, nombre_completo, nombre_cargo, nombre_unidad, sueldo_base, diferencia_cargo, sobre_promedio)
        VALUES (v_rut_medico, v_nombre_completo, v_nombre_cargo, v_nombre_unidad, v_sueldo_base, v_diferencia_cargo, v_sobre_promedio);
    
    END LOOP;
    -- Cerrar el cursor
    CLOSE cr_medicos;
END sp_generar_informes;
/




/* Valores para realizar las pruebas 
   del ejercicio */

-- Prueba de Procedimiento Almacenado 2 (principal)
BEGIN
    sp_generar_informes(p_id_unidad => 700, p_periodo => '06-2024'); -- Valores que coinciden con el ejemplo de las instrucciones.
END;
/

-- Revisar Tablas

SELECT * FROM DETALLE_ATENCIONES;

SELECT * FROM RESUMEN_MEDICO;
