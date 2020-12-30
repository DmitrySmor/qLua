--[[
	���������� � ������ STOP-������ (��������� ��� ��������)
	- ������ ���� ������ ���� �� ��� (������ ����� ����������� �� ������ ���������� �������� � STOP_TABLE)
	- �������� ����������� ���� ������� ���� �������� ������� (��������� ��� ��������)
	- ������� ���� ������ �� ����������� (����� �� �������) ���� �� ����� �� ������� ������� (������, �����)
	- ������� ��� �������� ����� �� ����������� (����� �� �������) ���� ������� ��������� �� �����
	- � ����� �������� ������ ��������� ��� ������� ������ � ���� ������ (���� �� ������������) 
	gfh
--]]

-- ������������� ���������
CLASS_CODE        	= "SPBFUT"; 						-- ��� ������ (SPBFUT - �������)
ACCOUNT_ID 			= "SPBFUT001tt"; 					-- ��������� ���� (����)
ACCOUNT_ID 			= "7655c4l"; 						-- ��������� ���� (�������)
STOP_INDENT 		= 200; 								-- ������ ������� ��� ����-������ (�� ���������)
STOP_TABLE 			= {									-- ������ ������� ������ ������ (�� ������������� ��������� ��� �������)
						BR  = 20,						-- ������ ������� ��� ����-������ BR 
						RTS = 200,						-- ������ ������� ��� ����-������ RTS 
						Si  = 50,						-- ������ ������� ��� ����-������ Si
					  }; 								


-- ������� ���������� ������ (������ �� �����)
Is_Run      		= true; 							-- ���� ������� ������� ����� ������� �� ����� �������


-- ����� ����� ��� ��� ���� ������������� ������� main()
function OnInit() 
	-- message("________ OnInit ________");	
end;

-- ������� ��������� �������
function OnStop()
	Is_Run = false;
end;

-- ������� ��������� ������ (SearchItems) ��� ������� �������� ���� ������� ��� ���������.
function SearchItems_stop_orders (flags, class_code)
	if bit.band(flags,0x1)==0x1 and class_code == CLASS_CODE then 
    	return true
	else
    	return false
   	end;
end;

-- ������� ���������� ���������� QUIK ��� ��������� ����� ����-������ ��� ��� ��������� ���������� ������������ ����-������.. 
function OnStopOrder(trans_reply)
	-- ��������� ��� �������� ������ �� ��������� ���� ��������� ���� ������
	if (trans_reply.balance == 0) then
		message("������� ��� �������� ������: "..trans_reply.sec_code  , 2);
		kill_all_futures_orders(trans_reply.sec_code);
	end;
end;

-- ������� �������� ����� � ����� ����� ��� (���������������)
function removeZero(str);
	str = tostring(str);
	while (string.sub(str,-1) == "0" and str ~= "0") do
		str = string.sub(str,1,-2)
	end;
	if (string.sub(str,-1) == ".") then 
		str = string.sub(str,1,-2)
	end;
   return str
end;

-- ������� �������� ������ �������, �������� � ��������� ������
function main() 
	-- main_BODY();
	while Is_Run do
		sleep(1000); -- ���� �������
		-- ��������� ������ ���� ���� ���������� � ��������
		if isConnected() then
			-- ���� �������
            main_BODY();
            else
            	message("CONNECTION STATE IS : " .. tostring(isConnected()), 3);
     	end;	
	end;
end;

function main_BODY()
	
	-- ��������� ������ �� ����� ���� ��������, ��� ����� ��� ������
	local array_class_code = {}; -- ��������������� ������, � ������� �� ��������
	for class_code in string.gmatch(getClassSecurities(CLASS_CODE), "(%w+)") do

		array_class_code[class_code] = { 
			pos_sum  		= 0, 			-- ������� �������� ������� � �����
			pos_price  		= 0, 			-- ����������� ���� ������� 
			stop_sum 		= 0, 			-- ������� ������� ���� ������ � �����
			stop_trans_id 	= 1001, 		-- ���������� ����������������� ����� ������, �������� �� �1� �� �2 147 483 647� 
			stop_order_id 	= 0, 			-- ���������� ����������������� ����� ������, �� ������� (� ����������� �� ��������������) 
			stop_price 		= nil, 			-- ����-����� ���� (���������� ��� ���������� ������ ���� ������)
			stop_indent 	= STOP_INDENT, 	-- ���� � ������� �� ���������
		};

		-- �������� �� ������������� ����� � STOP_TABLE, ���� ���� �� ������������� �� STOP_TABLE
		local base_active =  getSecurityInfo(CLASS_CODE, class_code).base_active_seccode;
		if (STOP_TABLE[base_active]) then 
			array_class_code[class_code]["stop_indent"] = STOP_TABLE[base_active]; 
		end;
	end;

	-- �������� ������ �� ��������  �� ������� "futures_client_holding" 
	if getNumberOf("futures_client_holding") then
		for i = 0, getNumberOf("futures_client_holding")-1 do
			-- �������� �� ������� ������ � ������� �� ������� i
			local position = getItem("futures_client_holding", i);

			-- ���������� ������ �� �������� �������
 			array_class_code[position.seccode]['pos_sum'] 	= tonumber(position.totalnet);  -- ����������� � ����� (���� �� ������ "-" �� ��� �������)
 			array_class_code[position.seccode]['pos_price'] = position.avrposnprice; 		-- ����������� ���� ������� 

			-- for key, val in pairs(position) do
			-- 	message(tostring(key).." - "..tostring(val));
			-- end;
			-- message("-------------")	
	   	end;
	end;

	-- �������� ������ �� ����-���� �������� (��������), �� ������� "stop_orders"
	local array = SearchItems("stop_orders", 0, getNumberOf("stop_orders")-1, SearchItems_stop_orders, "flags, class_code");
	if array then
		for i, id in pairs(array) do
		   	-- �������� �� ������� ������ � ������� �� ������� id
		   	local stopPos = getItem("stop_orders", id);

		   	-- ���������� ������ �� �������� ���� �������
			-- ����������� � ����� (���� �� ������ "-" �� ��� �������)
 			array_class_code[stopPos.sec_code]['stop_sum'] 			= tonumber(stopPos.qty); 	-- ������� ������� ���� ������ � �����
 			array_class_code[stopPos.sec_code]['stop_order_id'] 	= stopPos.order_num; 		-- ���������� ����������������� ����� ������, �� ������� (��� ������������ �������)
 			array_class_code[stopPos.sec_code]['stop_price'] 		= stopPos.condition_price2; -- ����-����� ���� (��� ������ ���� �����-������ � ����-�����) 
		end;
	end;
	
	-- ��������� ��������� ������ 
	for key, val in pairs(array_class_code) do
		
		-- ������(����) � ����(����) � ��� �� ����� ����� ������� ����
		if (val.pos_sum ~= 0  and val.stop_sum ~= 0 and math.abs(val.pos_sum) ~= math.abs(val.stop_sum)) then
			message(key..": pos_sum - "..val.pos_sum..", stop_sum - "..val.stop_sum);
			-- ������� ���� ������
			kill_stop_order(key, val);
			-- ������ ����� ���� ������
   			new_stop_order (key, val);

		-- ������(����) � ����(���) ��������� ����
		elseif (val.pos_sum ~= 0  and val.stop_sum == 0) then
			message(key..": pos_sum - "..val.pos_sum..", stop_sum - "..val.stop_sum);
			-- ������ ����� ���� ������
			new_stop_order (key, val);

		-- ������(���) � ����(����) ������� ����
		elseif (val.pos_sum == 0  and val.stop_sum ~= 0) then
			message(key..": pos_sum - "..val.pos_sum..", stop_sum - "..val.stop_sum);
			-- ������� ���� ������
			kill_stop_order(key, val);
		end;
	end;

end;

-- ���������� ���� ����� �� ����������.
function new_stop_order (seccode, val)

	local operation, condition, offset, stopprice2 = "B", "5", tostring(0), val.pos_price + val.stop_indent;
	-- ��� ������� ����
	if val.pos_sum > 0 then 
		operation, condition, offset, stopprice2 = "S", "4", tostring(0), val.pos_price - val.stop_indent;	
	end;
	-- ���� ���� ������ ���� ������, ����� ����-���� �� ������ ������
	if val.stop_price then stopprice2 = val.stop_price; end

	local Transaction = {
		['ACTION'] 					= "NEW_STOP_ORDER", 
		['EXPIRY_DATE'] 			= "TODAY",--"GTC", -- �� ������� ����� ������ ����-������ � ���������� �������, ����� �������� �� GTC
		['STOP_ORDER_KIND'] 		= "TAKE_PROFIT_AND_STOP_LIMIT_ORDER", -- ��� ����-������
		['MARKET_STOP_LIMIT'] 		= "YES",
		['MARKET_TAKE_PROFIT'] 		= "YES",
		['TYPE'] 					= "M",
		['ACCOUNT'] 				= ACCOUNT_ID,
		['CLASSCODE'] 				= CLASS_CODE,
		['CLIENT_CODE'] 			= ACCOUNT_ID, -- ����������� � ����������, ������� ����� ����� � �����������, ������� � ������� 
		['PRICE'] 					= "0", -- ����, �� ������� ���������� ������ ��� ������������ ����-����� (��� �������� ������ �� ������ ������ ���� 0)
		['STOPPRICE'] 				= "0", -- ���� ����-�������
		["STOPPRICE2"] 				= removeZero(stopprice2), -- ���� ����-�����
		["OFFSET"]  				= offset, -- �������� ������� �� ��������� (��������) ���� ��������� ������.
		['TRANS_ID'] 				= removeZero(val.stop_trans_id),
		['SECCODE'] 				= seccode,
		['OPERATION'] 				= operation, -- ����������� ������, ������������ ��������. ��������: �S� � �������, �B� � ������
		['CONDITION'] 				= condition, -- �������������� ����-����. ��������� ��������: �4� - ������ ��� �����, �5� � ������ ��� �����
		['QUANTITY']  				= tostring(math.abs(val.pos_sum)), -- ���������� ����� � ������, ������������ �������� 
	};

	local res = sendTransaction(Transaction);
	if res ~= "" then message('Error: '..res, 3); end;
end;

-- ������� ���� ����� �� ����������
function kill_stop_order (seccode,val)
	local Transaction = {
       ['ACTION'] 					= "KILL_STOP_ORDER", 
       ['CLASSCODE'] 				= CLASS_CODE,
       ['SECCODE'] 					= seccode,
       ['ACCOUNT'] 					= ACCOUNT_ID,
       ['CLIENT_CODE'] 				= ACCOUNT_ID, -- ����������� � ����������, ������� ����� ����� � �����������, ������� � ������� 
       ['TRANS_ID'] 				= removeZero(val.stop_trans_id), -- ID ��������� ����������
       ['STOP_ORDER_KEY'] 			= tostring(val.stop_order_id)
   	};
 
	local res = sendTransaction(Transaction);
	if res ~= "" then message('Error: '..res, 3); end;
end;

-- ������� ��� �������� �������� ������ �� ����������
function kill_all_futures_orders(seccode)
	local Transaction = {
       ['ACTION'] 					= "KILL_ALL_FUTURES_ORDERS", 
       ['CLASSCODE'] 				= CLASS_CODE,
       ['ACCOUNT'] 					= ACCOUNT_ID,
       ['CLIENT_CODE'] 				= ACCOUNT_ID, -- ����������� � ����������, ������� ����� ����� � �����������, ������� � ������� 
       ['TRANS_ID'] 				= "2002",
       ['SECCODE'] 					= seccode,
       ['BASE_CONTRACT'] 			= getSecurityInfo(CLASS_CODE, seccode).base_active_seccode,
   	};
	local res = sendTransaction(Transaction);
	if res ~= "" then message('Error: '..res, 3); end;
end;