--[[
	ПОСТАНОВКА И СНЯТИЕ STOP-ОРДЕРА (использую для фючерсов)
	- ставит стоп ордера если их нет (размер можно настраивать на каждый инструмент отдельно в STOP_TABLE)
	- изменяте колличестов стоп ордеров если выходишь частями (лимитками или маркетом)
	- удаляет стоп ордера по интсрументу (друге не трогает) если вы вышли из позиции целиком (маркет, лимит)
	- удаляет все лимитные ордра по интсрументу (друге не трогает) если позиция закрылась по Стопу
	- в конце вечерней ссесии закрывает все активне сделки и стоп ордера (пока не реализованна) 
	gfh
--]]

-- НАСТРАИВАЕМЫЕ ПАРАМЕТРЫ
CLASS_CODE        	= "SPBFUT"; 						-- Код класса (SPBFUT - фючерсы)
ACCOUNT_ID 			= "SPBFUT001tt"; 					-- Торговыий счет (Демо)
-- ACCOUNT_ID 			= "7655c4l"; 						-- Торговыий счет (Рабочий)
STOP_INDENT 		= 200; 								-- Отступ пунктах для Стоп-ордера (по умолчанию)
STOP_TABLE 			= {									-- Массив БАЗОВЫХ АТИВАХ Стопов (по необходимости добавлять или удалять)
						BR  = 20,						-- Отступ пунктах для Стоп-ордера BR 
						RTS = 200,						-- Отступ пунктах для Стоп-ордера RTS 
						Si  = 50,						-- Отступ пунктах для Стоп-ордера Si
					  }; 								


-- РАБОЧИЕ ПЕРЕМЕННЫЕ РОБОТА (менять не нужно)
Is_Run      		= true; 							-- Флаг запуска скрипта после нажатия на копку запуска


-- Здесь будет Ваш код пред инициализации функции main()
function OnInit() 
	-- message("________ OnInit ________");		
end;

-- Функция отсановки скрипта
function OnStop()
	Is_Run = false;
end;

-- Функция обратного вызова (SearchItems) для поиска активных стоп ордеров для фьюечрсов.
function SearchItems_stop_orders (flags, class_code)
	if bit.band(flags,0x1)==0x1 and class_code == CLASS_CODE then 
    	return true
	else
    	return false
   	end;
end;

-- Функция вызывается терминалом QUIK при получении новой стоп-заявки или при изменении параметров существующей стоп-заявки.. 
function OnStopOrder(trans_reply)
	-- Закрываем все лимитные сделки по истументу если сработала стоп заявка
	if (trans_reply.balance == 0) then
		message("Delete All limit orders: "..trans_reply.sec_code  , 2);
		kill_all_futures_orders(trans_reply.sec_code);
	end;
end;

-- Функция удаление точки и нулей после нее (Вспомогательная)
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

-- Функция основной логики скрипта, работает в отдельном потоке
function main() 
	-- main_BODY();
	while Is_Run do
		sleep(1000); -- одна сикунда
		-- Запускаем скрипт если есть соединенеи с сервером
		if isConnected() then
			-- тело скрипта
            main_BODY();
            else
            	message("CONNECTION STATE IS : " .. tostring(isConnected()), 3);
     	end;	
	end;
end;

function main_BODY()
	
	-- Локальный массив со всеми кода фючерсов, код будет как индекс
	local array_class_code = {}; -- перезаписываемы массив, с которым мы работаем
	for class_code in string.gmatch(getClassSecurities(CLASS_CODE), "(%w+)") do

		array_class_code[class_code] = { 
			pos_sum  		= 0, 			-- текущие открытые позиции в лотах
			pos_price  		= 0, 			-- Эффективная цена позиций 
			stop_sum 		= 0, 			-- текущие активне стоп ордера в лотах
			stop_trans_id 	= 1001, 		-- Уникальный идентификационный номер заявки, значение от «1» до «2 147 483 647» 
			stop_order_id 	= 0, 			-- Уникальный идентификационный номер заявки, от сервера (в дальнейщейм он презапивыеться) 
			stop_price 		= nil, 			-- Стоп-лимит цена (необходима для запоминаня старой стоп заявки)
			stop_indent 	= STOP_INDENT, 	-- Стоп в пунктах по умолчаняю
		};

		-- проверка на существоваиня стопа в STOP_TABLE, если есть то устанавливаем из STOP_TABLE
		local base_active =  getSecurityInfo(CLASS_CODE, class_code).base_active_seccode;
		if (STOP_TABLE[base_active]) then 
			array_class_code[class_code]["stop_indent"] = STOP_TABLE[base_active]; 
		end;
	end;

	-- Собираем данные по позициям  из таблицы "futures_client_holding" 
	if getNumberOf("futures_client_holding") then
		for i = 0, getNumberOf("futures_client_holding")-1 do
			-- получаем из таблицы строку с данными по индексу i
			local position = getItem("futures_client_holding", i);

			-- Записываем данные по открытой позиции
 			array_class_code[position.seccode]['pos_sum'] 	= tonumber(position.totalnet);  -- Колличество в лотах (если со знаком "-" то это продажа)
 			array_class_code[position.seccode]['pos_price'] = position.avrposnprice; 		-- Эффективная цена позиций 

			-- for key, val in pairs(position) do
			-- 	message(tostring(key).." - "..tostring(val));
			-- end;
			-- message("-------------")	
	   	end;
	end;

	-- Собираем данные по Стоп-Тейк позициям (АКТИВНЫЕ), из таблицы "stop_orders"
	local array = SearchItems("stop_orders", 0, getNumberOf("stop_orders")-1, SearchItems_stop_orders, "flags, class_code");
	if array then
		for i, id in pairs(array) do
		   	-- получаем из таблицы строку с данными по индексу id
		   	local stopPos = getItem("stop_orders", id);

		   	-- Записываем данные по открытой Стоп позиции
			-- Колличество в лотах (если со знаком "-" то это продажа)
 			array_class_code[stopPos.sec_code]['stop_sum'] 			= tonumber(stopPos.qty); 	-- текущие активне стоп ордера в лотах
 			array_class_code[stopPos.sec_code]['stop_order_id'] 	= stopPos.order_num; 		-- Уникальный идентификационный номер заявки, от сервера (для последующего удаленя)
 			array_class_code[stopPos.sec_code]['stop_price'] 		= stopPos.condition_price2; -- Стоп-лимит цена (для заявок типа «Тэйк-профит и стоп-лимит») 
		end;
	end;
	
	-- Проверяем сосотяние позицй 
	for key, val in pairs(array_class_code) do
		
		-- Пзиция(есть) и Стоп(есть) и они не равны тогда удаляем стоп
		if (val.pos_sum ~= 0  and val.stop_sum ~= 0 and math.abs(val.pos_sum) ~= math.abs(val.stop_sum)) then
			message(key..": pos_sum - "..val.pos_sum..", stop_sum - "..val.stop_sum);
			-- Удаляем стоп заявку
			kill_stop_order(key, val);
			-- Ставим новую стоп заявку
   			new_stop_order (key, val);

		-- Пзиция(есть) и Стоп(нет) добовляем стоп
		elseif (val.pos_sum ~= 0  and val.stop_sum == 0) then
			message(key..": pos_sum - "..val.pos_sum..", stop_sum - "..val.stop_sum);
			-- Ставим новую стоп заявку
			new_stop_order (key, val);

		-- Пзиция(нет) и Стоп(есть) удаляем стоп
		elseif (val.pos_sum == 0  and val.stop_sum ~= 0) then
			message(key..": pos_sum - "..val.pos_sum..", stop_sum - "..val.stop_sum);
			-- Удаляем стоп заявку
			kill_stop_order(key, val);
		end;
	end;

end;

-- Выставляем стоп ордер по инстументу.
function new_stop_order (seccode, val)

	local operation, condition, offset, stopprice2 = "B", "5", tostring(0), val.pos_price + val.stop_indent;
	-- Для позиции лонг
	if val.pos_sum > 0 then 
		operation, condition, offset, stopprice2 = "S", "4", tostring(0), val.pos_price - val.stop_indent;	
	end;
	-- Если есть старая стоп заявка, берем стоп-цену из старой заявки
	if val.stop_price then stopprice2 = val.stop_price; end

	local Transaction = {
		['ACTION'] 					= "NEW_STOP_ORDER", 
		['EXPIRY_DATE'] 			= "TODAY",--"GTC", -- на учебном серве только стоп-заявки с истечением сегодня, потом поменять на GTC
		['STOP_ORDER_KIND'] 		= "TAKE_PROFIT_AND_STOP_LIMIT_ORDER", -- Тип стоп-заявки
		['MARKET_STOP_LIMIT'] 		= "YES",
		['MARKET_TAKE_PROFIT'] 		= "YES",
		['TYPE'] 					= "M",
		['ACCOUNT'] 				= ACCOUNT_ID,
		['CLASSCODE'] 				= CLASS_CODE,
		['CLIENT_CODE'] 			= ACCOUNT_ID, -- Комментарий к транзакции, который будет виден в транзакциях, заявках и сделках 
		['PRICE'] 					= "0", -- Цена, по которой выставится заявка при срабатывании Стоп-Лосса (для рыночной заявки по акциям должна быть 0)
		['STOPPRICE'] 				= "0", -- Цена Тэйк-Профита
		["STOPPRICE2"] 				= removeZero(stopprice2), -- Цена Стоп-Лосса
		["OFFSET"]  				= offset, -- Величина отступа от максимума (минимума) цены последней сделки.
		['TRANS_ID'] 				= removeZero(val.stop_trans_id),
		['SECCODE'] 				= seccode,
		['OPERATION'] 				= operation, -- Направление заявки, обязательный параметр. Значения: «S» – продать, «B» – купить
		['CONDITION'] 				= condition, -- Направленность стоп-цены. Возможные значения: «4» - меньше или равно, «5» – больше или равно
		['QUANTITY']  				= tostring(math.abs(val.pos_sum)), -- Количество лотов в заявке, обязательный параметр 
	};

	local res = sendTransaction(Transaction);
	if res ~= "" then message('Error: '..res, 3); end;
end;

-- Удаляем Стоп ордер по инстументу
function kill_stop_order (seccode,val)
	local Transaction = {
       ['ACTION'] 					= "KILL_STOP_ORDER", 
       ['CLASSCODE'] 				= CLASS_CODE,
       ['SECCODE'] 					= seccode,
       ['ACCOUNT'] 					= ACCOUNT_ID,
       ['CLIENT_CODE'] 				= ACCOUNT_ID, -- Комментарий к транзакции, который будет виден в транзакциях, заявках и сделках 
       ['TRANS_ID'] 				= removeZero(val.stop_trans_id), -- ID УДАЛЯЮЩЕЙ транзакции
       ['STOP_ORDER_KEY'] 			= tostring(val.stop_order_id)
   	};
 
	local res = sendTransaction(Transaction);
	if res ~= "" then message('Error: '..res, 3); end;
end;

-- Удаляем все активные лимитные заявки по иструменту
function kill_all_futures_orders(seccode)
	local Transaction = {
       ['ACTION'] 					= "KILL_ALL_FUTURES_ORDERS", 
       ['CLASSCODE'] 				= CLASS_CODE,
       ['ACCOUNT'] 					= ACCOUNT_ID,
       ['CLIENT_CODE'] 				= ACCOUNT_ID, -- Комментарий к транзакции, который будет виден в транзакциях, заявках и сделках 
       ['TRANS_ID'] 				= "2002",
       ['SECCODE'] 					= seccode,
       ['BASE_CONTRACT'] 			= getSecurityInfo(CLASS_CODE, seccode).base_active_seccode,
   	};
	local res = sendTransaction(Transaction);
	if res ~= "" then message('Error: '..res, 3); end;
end;