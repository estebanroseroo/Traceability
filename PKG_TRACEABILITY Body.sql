create or replace PACKAGE BODY "PKG_TRACEABILITY" IS

FUNCTION error(p_code in varchar2, p_msg in varchar2, p_id in number, p_type in varchar2)
return boolean is
code varchar2(20); msg varchar2(400);
BEGIN
rollback; code:=substr(p_code,1,20); msg:=substr(p_msg,1,400);
if p_type = 'M' then
    update tbl_app_producto set estado='E', fechaproblema=sysdate, comentario='CODE:'||code||' MSG:'||msg where id=p_id;
    update tbl_app_producto_detalle set estado='E' where producto_id=p_id;
else
    update tbl_app_activo set estado='E', fechaproblema=sysdate, comentario='CODE:'||code||' MSG:'||msg where id=p_id;
end if;
commit; return false;
END;
-------------------------------------------------------------------------------------------------------------
FUNCTION stock(p_flag out boolean, p_msg out varchar2, p_warehouse in number, p_item in number)
return boolean is
total number;
BEGIN
p_flag:=true;
begin
select coalesce(SUM(s.cantidad),0) into total 
from tbl_web_stock s 
inner join tbl_web_bodega b on b.id=s.bodega_id
inner join tbl_web_item i on i.id=s.item_id
where s.anio=to_char(sysdate,'YYYY') and s.mes=to_char(sysdate,'mm') and s.bodega_id=p_warehouse and s.item_id=p_item;
exception when others then p_flag:=false; p_msg:='Stock incompleto en bodega '||p_warehouse||' item '||p_item||sqlerrm; return false;
end;
return true;
END;
-------------------------------------------------------------------------------------------------------------
FUNCTION bodega(p_flag out boolean, p_msg out varchar2, p_asset in number, p_company in number) 
return boolean is
bodegaDestino varchar2(20);
BEGIN
p_flag:=true;
begin
select case when ma.codigo='tra' then bd.codigo else b.codigo end into bodegaDestino 
from tbl_web_activo a 
inner join tbl_web_activo_ubicacion au on a.id=au.activo_id 
inner join tbl_web_motivo_activo ma on ma.id=a.motivoactivo_id 
inner join tbl_web_bodega b on b.id=au.bodega_id 
left join tbl_web_bodega bd on bd.id=au.bodegadestino_id 
where a.empresa_id=p_company and a.id=p_asset and ma.codigo in ('TRA','ING','EGR');
exception when others then p_flag:=false; p_msg:='No existe ubicacion del activo '||p_asset||sqlerrm; return false;
end;
return true;
END;
-------------------------------------------------------------------------------------------------------------
PROCEDURE serial(p_flag out boolean, p_msg out varchar2, p_warehouse in number, p_transaction in number, p_user in number) IS
v_empresa varchar2(100); v_codigo varchar2(40);
BEGIN
p_flag:=true;
begin
select descripcion into v_empresa from tbl_web_empresa where bodega_id=p_warehouse;
v_codigo:=esquema_administracion.f_secuencia_activo(p_warehouse, v_empresa);
exception when others then p_flag:=false; p_msg:='Funcion f_secuencia_activo '||sqlerrm;
end;
if p_flag then
    if p_transaction is not null then
        update tbl_web_activo set origen='E' where transaccion_id=p_transaction and estado='A';
    else
        begin
        insert into tbl_web_activo(empresa_id, tipoactivo_id, usuario_id, serial, fecha, observacion, estado, tipocontenido_id, origen)
        select p_empresa, ma.tipoactivo_id, p_user, ma.serial, sysdate, 'serial', 'A', ma.tipocontenido_id, 'M'
        from tbl_app_activo ma where ma.id=p_transaction;
        exception when others then p_flag:=false; p_msg:='Crear activo '||sqlerrm;
        end;
    end if;
end if;
END serial;
-------------------------------------------------------------------------------------------------------------
PROCEDURE activo(p_flag out boolean, p_msg out varchar2, p_warehouse in number, p_next_warehouse in number, p_assets in VARRAYNUMBER,
p_transaction in number, p_user in number) IS
BEGIN
p_flag:=true;
begin
insert into tbl_web_transaccion(id, fecha, usuario_id, observacion, estado, origen)
values(p_transaction, sysdate, p_user, 'transaccion', 'I', 'M');
exception when others then p_flag:=false; p_msg:='Crear transaccion '||sqlerrm;
end;
if p_bandera then
    for i in p_assets.first..p_assets.last loop
        if p_bandera then
            begin
            insert into tbl_web_transaccion_detalle(transaccion_id, activo_id, observacion, estado, bodega_id, bodegadestino_id, cantidad)
            values(p_transaction, p_assets(i), 'version 1.0.0', 'A', p_warehouse, p_next_warehouse, 1);
            exception when others then p_flag:=false; p_msg:='Crear transaccion detalle '||sqlerrm;
            end;
        end if;
    end loop;
end if;
END activo;
-------------------------------------------------------------------------------------------------------------
PROCEDURE producto(p_flag out boolean, p_msg out varchar2, p_assets in VARRAYNUMBER, p_product in number, p_user in number, 
p_company in number, p_bill in boolean) IS
v_query varchar2(400); v_secuencia number; v_bodega number(10); v_configuracion varchar2(40); v_contador number;
v_detalles VARRAYNUMBER; v_items VARRAYNUMBER; v_repetido number; v_id number(10);
BEGIN
p_flag:=true;
begin 
v_query:='select '||'SEC_'||p_company||'.nextval from dual';
execute immediate v_query into v_secuencia;
exception when others then p_flag:=false; p_msg:='Codigo secuencia '||sqlerrm;
end;
if p_flag and p_bill then
    v_configuracion:='SSSNN';
    begin
    select m.bodega_id into v_bodega 
    from tbl_app_producto m
    inner join tbl_app_perfil p on p.id=m.perfil_id where m.id=p_product;
    exception when others then p_flag:=false; p_msg:='Obtener bodega '||sqlerrm;
    end;
else
    v_configuracion:='NSSNN'; 
    v_bodega:=null;
end if;
if p_flag then
    begin
    insert into tbl_web_producto(tipodocumento_id, bodega_id, bodegadestino_id, usuario_id, codigo, 
    fecha, observacion, configuracion, estado, origen)
    select m.tipodocumento_id, v_bodega, m.bodegadestino_id, p_user,
    ((select etiqueta from tbl_web_empresa where id=p_company)||'-'||v_secuencia), m.fecha, 
    'producto', v_configuracion, 'I', 'M'
    from tbl_app_producto m
    inner join tbl_web_bodega b on b.id=m.bodega_id 
    where m.id=p_product;
    exception when others then p_flag:=false; p_msg:='Producto crear '||sqlerrm;
    end;
end if;
if p_flag then
    v_contador:=0; v_detalles:=VARRAYNUMBER(); v_items:=VARRAYNUMBER();
    for i in p_assets.first..p_assets.last loop
        v_repetido:=0;
        for detalle in (select md.id, md.item_id from tbl_app_producto_detalle md 
        inner join tbl_producto_activo ma on md.id=ma.producto_detalle_id where md.producto_id=p_product and ma.id=p_assets(i)) loop
            if v_items.first is not null then
                for i in v_items.first..v_items.last loop
                    if detalle.item_id = v_items(i) then
                        v_repetido:=v_repetido+1; v_id:=v_detalles(i); exit;
                    end if;
                end loop;
            end if;
            if v_repetido > 0 then
                begin
                update tbl_web_producto_detalle set cantidad=cantidad-1 where id=v_id;
                exception when others then p_flag:=false; p_msg:='Producto detalle actualizar '||sqlerrm;
                end;
            else
                begin
                insert into tbl_web_producto_detalle(producto_id, item_id, cantidad)
                select p_producto, md.item_id, 1
                from tbl_app_producto_detalle md
                inner join tbl_app_producto m on m.id=md.producto_id
                where md.id=detalle.id;
                exception when others then p_flag:=false; p_msg:='Producto detalle crear '||sqlerrm;
                end;
            end if;    
        end loop;    
    end loop;            
end if; 
END producto;
-------------------------------------------------------------------------------------------------------------
PROCEDURE menu(p_code in out varchar2, p_msg in out varchar2) IS
cursor c is select distinct id, pantalla from tbl_app_producto where estado='I';
v_code varchar2(20); v_msg varchar2(400); v_id number(10); v_pantalla varchar2(1);
BEGIN
for c_cursor in c loop
    v_id:=c_cursor.id; v_pantalla:=c_cursor.pantalla;
    if v_pantalla = 'I' then dbms_output.put_line('Ingreso'); ingreso(v_code, v_msg, v_id);
    elsif v_pantalla = 'T' then dbms_output.put_line('Transferencia'); transferencia(v_code, v_msg, v_id);
    else dbms_output.put_line('Egreso'); egreso(v_code, v_msg, v_id);
    end if;
end loop;
EXCEPTION WHEN OTHERS THEN v_msg:=SUBSTR(SQLERRM,1,400); dbms_output.put_line('Error en PKG_TRACEABILITY.menu '||v_msg);
END menu;
-------------------------------------------------------------------------------------------------------------
PROCEDURE ingreso(p_code in out varchar2, p_msg in out varchar2, p_id in number) IS
cursor c is select distinct id from tbl_app_producto where estado='I' and pantalla='I' and id=p_id;
v_flag boolean; v_arreglo VARRAYNUMBER; v_msg varchar2(4000); v_contador number; v_webservice varchar2(4000);  
BEGIN
for c_cursor in c loop
    v_flag:=true;
    v_contador:=0; v_arreglo:=VARRAYNUMBER();
    for activo in (select ma.activo_id from tbl_app_producto_activo ma
    inner join tbl_app_producto_detalle md on md.id=ma.producto_detalle_id where md.producto_id=p_id) loop
    	v_contador:=v_contador+1; v_arreglo.extend(1);
        for i in 1..v_contador loop
		if v_arreglo(i) is null then v_arreglo(i):=activo.activo_id; end if;
        end loop;
    end loop;
    activo(v_flag, v_msg, activo.bodega_id, activo.bodegadestino_id, v_arreglo, p_id, activo.user_id);
    if v_flag=false then v_flag:=error('activo', v_msg, p_id); end if;
    if v_flag then
        begin
        v_webservice:= UTL_HTTP.REQUEST('http://192.168.1.1:8080/webservice/procesa_activo?id='||to_char(p_id)||'&proceso=ACTIVO&pantalla=1');       
        dbms_output.put_line('PROCESAR ACTIVO '||v_webservice||', ID:'||p_id);
        exception when others then 
            v_flag:=error('procesar activo', sqlerrm, p_id); 
            update tbl_app_producto set estado='X' where id=p_id; commit;
        end;
    end if;
    if v_flag then
        update tbl_app_producto set estado='P', fechaproblema=null, comentario=null where id=p_id;
        update tbl_app_producto_detalle set estado='P' where producto_id=p_id;
        update tbl_app_producto_activo set estado='P' where producto_detalle_id in (select id from tbl_app_producto_detalle where producto_id=p_id);
        if v_flag then commit; end if;
    end if;
end loop;
EXCEPTION WHEN OTHERS THEN
    v_msg:=SUBSTR(SQLERRM,1,400); rollback;
    update tbl_app_producto set estado='E', fechaproblema=sysdate, comentario='ingreso '||v_msg where id=p_id; 
    update tbl_app_producto_detalle set estado='E' where producto_id=p_id;
    update tbl_app_producto_activo set estado='E' where producto_detalle_id in (select id from tbl_app_producto_detalle where producto_id=p_id);
    commit;
END ingreso;
-------------------------------------------------------------------------------------------------------------
PROCEDURE transferencia(p_code in out varchar2, p_msg in out varchar2, p_id in number) IS
cursor c is select distinct id from tbl_app_producto where estado='I' and pantalla='T' and id=p_id;
v_flag boolean; v_arreglo VARRAYNUMBER; v_msg varchar2(4000); v_contador number; v_webservice varchar2(4000);  
v_lleno number; v_arreglolleno VARRAYNUMBER; v_estado varchar2(1);
BEGIN
for c_cursor in c loop
    v_flag:=true;
    v_contador:=0; v_lleno:=0; v_arreglo:=VARRAYNUMBER(); v_arreglolleno:=VARRAYNUMBER();
    for activo in (select ma.activo_id from tbl_app_producto_activo ma
    inner join tbl_app_producto_detalle md on md.id=ma.producto_detalle_id where md.producto_id=p_id) loop
 	v_flag:=bodega(v_flag, v_msg, activo.activo_id, activo.empresa_id);
        if v_flag=false then v_flag:=error('bodega', v_msg, p_id); exit; end if;
    	v_contador:=v_contador+1; v_arreglo.extend(1);
        for i in 1..v_contador loop
		if v_arreglo(i) is null then v_arreglo(i):=activo.activo_id; end if;
        end loop;
  	if v_flag and activo.lleno = 'S' then
        	v_lleno:=v_lleno+1; v_arreglolleno.extend(1);
                for i in 1..v_lleno loop
                    if v_arreglolleno(i) is null then v_arreglolleno(i):=activo.id; end if;
                end loop;
        end if;
    end loop;
    if v_flag then
    	activo(v_flag, v_msg, activo.bodega_id, activo.bodegadestino_id, v_arreglo, p_id, activo.user_id);
     	if v_flag=false then v_flag:=error('activo', v_msg, p_id); end if;
    end if;
    if v_flag and v_lleno > 0 then
        producto(v_flag, v_msg, v_arreglolleno, p_id, activo.user_id, activo.empresa_id, false);
        if v_flag=false then v_flag:=error('producto', v_msg, p_id); end if;
    end if;
    if v_flag and v_lleno > 0 then
        for detalle in (select m.bodega_id, d.item_id from tbl_web_producto_detalle d
        inner join tbl_web_producto m on m.id=d.producto_id where d.producto_id=p_id) loop
            v_flag:=stock(v_flag, v_msg, detalle.bodega_id, detalle.item_id);
            if v_flag=false then v_flag:=error('stock', v_msg, p_id); end if;
        end loop;
    end if;
    if v_flag then
        begin
        v_webservice:= UTL_HTTP.REQUEST('http://192.168.1.1:8080/webservice/procesa_activo?id='||to_char(p_id)||'&proceso=ACTIVO&pantalla=2');       
        dbms_output.put_line('PROCESAR ACTIVO '||v_webservice||', ID:'||p_id);
        exception when others then 
            v_flag:=error('procesar activo', sqlerrm, p_id); 
            update tbl_app_producto set estado='X' where id=p_id; commit;
        end;
    end if;
    if v_flag and v_lleno > 0 then
        begin
        v_webservice:= UTL_HTTP.REQUEST('http://192.168.1.1:8080/webservice/procesa_producto?id='||to_char(p_id)||'&proceso=PRODUCTO&pantalla=2');       
        dbms_output.put_line('PROCESAR PRODUCTO '||v_webservice||', ID:'||p_id);
        exception when others then 
	    v_flag:=error('procesar producto', sqlerrm, p_id); 
            update tbl_app_producto set estado='X' where id=p_id; commit;
        end;
        if v_flag then
            begin
            select estado into v_estado from tbl_web_producto where id=p_id;
            exception when others then v_flag:=error('estado procesar producto', sqlerrm, p_id);
            end;
            if v_estado != 'A' then
	        v_flag:=error('estado producto', sqlerrm, p_id); 
                update tbl_app_producto set estado='X' where id=p_id; commit;
            end if;
        end if;
    end if;
    if v_flag then
        update tbl_app_producto set estado='P', fechaproblema=null, comentario=null where id=p_id;
        update tbl_app_producto_detalle set estado='P' where producto_id=p_id;
        update tbl_app_producto_activo set estado='P' where producto_detalle_id in (select id from tbl_app_producto_detalle where producto_id=p_id);
        if v_flag then commit; end if;
    end if;
end loop;
EXCEPTION WHEN OTHERS THEN
    v_msg:=SUBSTR(SQLERRM,1,400); rollback;
    update tbl_app_producto set estado='E', fechaproblema=sysdate, comentario='transferencia '||v_msg where id=p_id; 
    update tbl_app_producto_detalle set estado='E' where producto_id=p_id;
    update tbl_app_producto_activo set estado='E' where producto_detalle_id in (select id from tbl_app_producto_detalle where producto_id=p_id);
    commit;
END transferencia;
-------------------------------------------------------------------------------------------------------------
PROCEDURE egreso(p_code in out varchar2, p_msg in out varchar2, p_id in number) IS
cursor c is select distinct id from tbl_app_producto where estado='I' and pantalla='E' and id=p_id;
v_flag boolean; v_arreglo VARRAYNUMBER; v_msg varchar2(4000); v_contador number; v_webservice varchar2(4000);  
v_lleno number; v_arreglolleno VARRAYNUMBER; v_estado varchar2(1);
BEGIN
for c_cursor in c loop
    v_flag:=true;
    v_contador:=0; v_lleno:=0; v_arreglo:=VARRAYNUMBER(); v_arreglolleno:=VARRAYNUMBER();
    for activo in (select ma.activo_id, ma.serial, ma.tipo, ma.bodega_id, ma.user_id from tbl_app_producto_activo ma
    inner join tbl_app_producto_detalle md on md.id=ma.producto_detalle_id where md.producto_id=p_id) loop
	if activo.serial is not null and activo.tipo = 'E' then
		v_flag:=serial(v_flag, v_msg, activo.bodega_id, p_id, activo.user_id);
        	if v_flag=false then v_flag:=error('serial', v_msg, p_id); exit; end if;
	end if;
 	v_flag:=bodega(v_flag, v_msg, activo.activo_id, activo.empresa_id);
        if v_flag=false then v_flag:=error('bodega', v_msg, p_id); exit; end if;
    	v_contador:=v_contador+1; v_arreglo.extend(1);
        for i in 1..v_contador loop
		if v_arreglo(i) is null then v_arreglo(i):=activo.activo_id; end if;
        end loop;
  	if v_flag and activo.lleno = 'S' then
        	v_lleno:=v_lleno+1; v_arreglolleno.extend(1);
                for i in 1..v_lleno loop
                    if v_arreglolleno(i) is null then v_arreglolleno(i):=activo.id; end if;
                end loop;
        end if;
    end loop;
    if v_flag then
    	activo(v_flag, v_msg, activo.bodega_id, activo.bodegadestino_id, v_arreglo, p_id, activo.user_id);
     	if v_flag=false then v_flag:=error('activo', v_msg, p_id); end if;
    end if;
    if v_flag and v_lleno > 0 then
        producto(v_flag, v_msg, v_arreglolleno, p_id, activo.user_id, activo.empresa_id, false);
        if v_flag=false then v_flag:=error('producto', v_msg, p_id); end if;
    end if;
    if v_flag and v_lleno > 0 then
        for detalle in (select m.bodega_id, d.item_id from tbl_web_producto_detalle d
        inner join tbl_web_producto m on m.id=d.producto_id where d.producto_id=p_id) loop
            v_flag:=stock(v_flag, v_msg, detalle.bodega_id, detalle.item_id);
            if v_flag=false then v_flag:=error('stock', v_msg, p_id); end if;
        end loop;
    end if;
    if v_flag then
        begin
        v_webservice:= UTL_HTTP.REQUEST('http://192.168.1.1:8080/webservice/procesa_activo?id='||to_char(p_id)||'&proceso=ACTIVO&pantalla=2');       
        dbms_output.put_line('PROCESAR ACTIVO '||v_webservice||', ID:'||p_id);
        exception when others then 
            v_flag:=error('procesar activo', sqlerrm, p_id); 
            update tbl_app_producto set estado='X' where id=p_id; commit;
        end;
    end if;
    if v_flag and v_lleno > 0 then
        begin
        v_webservice:= UTL_HTTP.REQUEST('http://192.168.1.1:8080/webservice/procesa_producto?id='||to_char(p_id)||'&proceso=PRODUCTO&pantalla=2');       
        dbms_output.put_line('PROCESAR PRODUCTO '||v_webservice||', ID:'||p_id);
        exception when others then 
	    v_flag:=error('procesar producto', sqlerrm, p_id); 
            update tbl_app_producto set estado='X' where id=p_id; commit;
        end;
        if v_flag then
            begin
            select estado into v_estado from tbl_web_producto where id=p_id;
            exception when others then v_flag:=error('estado procesar producto', sqlerrm, p_id);
            end;
            if v_estado != 'A' then
	        v_flag:=error('estado producto', sqlerrm, p_id); 
                update tbl_app_producto set estado='X' where id=p_id; commit;
            end if;
        end if;
    end if;
    if v_flag then
        update tbl_app_producto set estado='P', fechaproblema=null, comentario=null where id=p_id;
        update tbl_app_producto_detalle set estado='P' where producto_id=p_id;
        update tbl_app_producto_activo set estado='P' where producto_detalle_id in (select id from tbl_app_producto_detalle where producto_id=p_id);
        if v_flag then commit; end if;
    end if;
end loop;
EXCEPTION WHEN OTHERS THEN
    v_msg:=SUBSTR(SQLERRM,1,400); rollback;
    update tbl_app_producto set estado='E', fechaproblema=sysdate, comentario='transferencia '||v_msg where id=p_id; 
    update tbl_app_producto_detalle set estado='E' where producto_id=p_id;
    update tbl_app_producto_activo set estado='E' where producto_detalle_id in (select id from tbl_app_producto_detalle where producto_id=p_id);
    commit;
END egreso;

END PKG_TRACEABILITY;