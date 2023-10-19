create or replace PACKAGE "PKG_TRACEABILITY" IS

FUNCTION error(p_code in varchar2, p_msg in varchar2, p_id in number, p_type in varchar2)
return boolean;

FUNCTION stock(p_flag out boolean, p_msg out varchar2, p_warehouse in number, p_item in number) 
return boolean;

FUNCTION bodega(p_flag out boolean, p_msg out varchar2, p_asset in number, p_company in number) 
return boolean;

PROCEDURE serial(p_flag out boolean, p_msg out varchar2, p_warehouse in number, p_transaction in number, p_user in number);

PROCEDURE activo(p_flag out boolean, p_msg out varchar2, p_warehouse in number, p_next_warehouse in number, p_assets in VARRAYNUMBER,
p_transaction in number, p_user in number);

PROCEDURE producto(p_flag out boolean, p_msg out varchar2, p_assets in VARRAYNUMBER, p_product in number, p_user in number, 
p_company in number, p_bill in boolean);

PROCEDURE menu(p_code in out varchar2, p_msg in out varchar2);

PROCEDURE ingreso(p_code in out varchar2, p_msg in out varchar2, p_id in number);

PROCEDURE transferencia(p_code in out varchar2, p_msg in out varchar2, p_id in number);

PROCEDURE egreso(p_code in out varchar2, p_msg in out varchar2, p_id in number);

END PKG_TRACEABILITY;