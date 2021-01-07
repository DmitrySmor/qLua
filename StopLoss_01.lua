--[[
	ПОСТАНОВКА И СНЯТИЕ STOP-ОРДЕРА (использую для торговли фючерсов внутри дня)
	- ставит стоп ордера если их нет (размер можно настраивать на каждый инструмент отдельно в STOP_TABLE)
	- изменяте колличестов стоп ордеров если выходишь частями (лимитками или маркетом)
	- удаляет стоп ордера по интсрументу (другие не трогает) если вы вышли из позиции целиком (маркет, лимит)
	- удаляет все лимитные ордра по интсрументу (другие не трогает) если позиция закрылась по Стопу
	- закрывает все активне сделки, стоп и лимитные ордера по времени
--]]

-- НАСТРАИВАЕМЫЕ ПАРАМЕТРЫ
CLASS_CODE      	= "SPBFUT"; 						-- Код класса (SPBFUT - фючерсы)
ACCOUNT_ID 				= "SPBFUT001tt"; 				-- Торговыий счет (Демо)
ACCOUNT_ID 				= "7655c4l"; 						-- Торговыий счет (Рабочий)
TIME_CLOSE				= "23:30:00";						-- Время закрытия позици и связанные с ним заявками
STOP_INDENT 			= 200; 									-- Отступ пунктах для Стоп-ордера (по умолчанию)
STOP_TABLE 				= {											-- Массив БАЗОВЫХ АТИВАХ Стопов (по необходимости добавлять или удалять)
	BR  = 20,																-- Отступ пунктах для Стоп-ордера BR
	RTS = 200,															-- Отступ пунктах для Стоп-ордера RTS
	Si  = 50,																-- Отступ пунктах для Стоп-ордера Si
};
Is_Run      			= true; 								-- Флаг запуска скрипта после нажатия на копку запуска

-- Функция инициализации функции main()
function OnInit()
end;

-- Функция остановки скрипта
function OnStop()
	Is_Run = false;
end;

-- Функция обратного вызова (SearchItems) для поиска активных стоп ордеров для фьючерсов.
function SearchItems_stop_orders (flags, class_code)
	if bit.band(flags,0x1)==0x1 and class_code == CLASS_CODE then return true else return false end;
end;

-- Функция вызывается терминалом QUIK при получении новой стоп-заявки или при изменении параметров существующей стоп-заявки..
function OnStopOrder(trans_reply)
	-- Закрываем все лимитные сделки по истументу если сработала стоп заявка
	if (trans_reply.balance == 0) then
		message("Delete All limit orders: "..trans_reply.sec_code  , 2);
		kill_all_futures_orders(trans_reply.sec_code);
	end;
end;

-- Функция удаление точки и нулей после нее (Вспомогательная функция)
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
	-- Локальный массив со всеми кода фючерсов, код будет как индекс
	local array_class_code = {}; -- перезаписываемы массив, с которым мы работаем
	-- Заполняем массив с посоянными данными
	for sec_code in string.gmatch(getClassSecurities(CLASS_CODE), "(%w+)") do
		array_class_code[sec_code] = {
			stop_trans_id 	= 1001, 				-- Уникальный идентификационный номер заявки, значение от «1» до «2 147 483 647»
			stop_indent 		= STOP_INDENT, 	-- Стоп в пунктах по умолчаняю
		};

		-- Узнаем какой базовый актив у инструмента
		local base_active =  getSecurityInfo(CLASS_CODE, sec_code).base_active_seccode;
		-- проверка на существоваиня стопа в STOP_TABLE, если есть то устанавливаем из STOP_TABLE
		if (STOP_TABLE[base_active]) then
			array_class_code[sec_code].stop_indent = STOP_TABLE[base_active];
		end;

	end;

	while Is_Run do
		sleep(1000); -- одна сикунда = 1000
		-- Запускаем скрипт если есть соединение с сервером
		if isConnected() then
      -- main_BODY(array_class_code); -- тело скрипта
        else
        	message("CONNECTION STATE IS : " .. tostring(isConnected()), 3);
   	end;
	end;
end;

function main_BODY(array_class_code)

	-- Добовляем в массив перезаписываемые значение
	for key, val in pairs(array_class_code) do
		array_class_code[key]["pos_sum"] 				= 0 			-- текущие открытые позиции в лотах
		array_class_code[key]["pos_price"] 			= 0 			-- Эффективная цена позиции
		array_class_code[key]["stop_sum"] 			= 0 			-- текущие активне стоп ордера в лотах
		array_class_code[key]["stop_order_id"] 	= 0 			-- Уникальный идентификационный номер заявки, от сервера (в дальнейщейм он презапивыеться)
		array_class_code[key]["stop_price"] 		= nil 		-- Стоп-лимит цена откртой позици (необходима для запоминаня старой стоп заявки)
	end;

	-- Собираем данные по открытым позициям  из таблицы "futures_client_holding"
	if getNumberOf("futures_client_holding") then
		for i = 0, getNumberOf("futures_client_holding")-1 do
			-- получаем из таблицы строку с данными по индексу i
			local position = getItem("futures_client_holding", i);

			-- Записываем данные по открытой позиции
			array_class_code[position.seccode]['pos_sum'] 	= tonumber(position.totalnet);  -- Колличество в лотах (если со знаком "-" то это продажа)
			array_class_code[position.seccode]['pos_price'] = position.avrposnprice; 		-- Эффективная цена позиций
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
			array_class_code[stopPos.sec_code]['stop_sum'] 				= tonumber(stopPos.qty); 	-- текущие активне стоп ордера в лотах
			array_class_code[stopPos.sec_code]['stop_order_id'] 	= stopPos.order_num; 		-- Уникальный идентификационный номер заявки, от сервера (для последующего удаленя)
			array_class_code[stopPos.sec_code]['stop_price'] 			= stopPos.condition_price2; -- Стоп-лимит цена (для заявок типа «Тэйк-профит и стоп-лимит»)
		end;
	end;

	-- Проверяем сосотяние позицй
	for key, val in pairs(array_class_code) do
		-- Позиция(есть) и Стоп(есть) и они не равны тогда удаляем стоп (при следующем проходе цикла он поставиться с нужным колличестовом)
		if (val.pos_sum ~= 0  and val.stop_sum ~= 0 and math.abs(val.pos_sum) ~= math.abs(val.stop_sum)) then
			message(key..": pos_sum - "..val.pos_sum..", stop_sum - "..val.stop_sum.." Removing these stop orders", 2);
			-- Удаляем стоп заявку
			kill_stop_order(key, val);

		-- Позиция(есть) и Стоп(нет) добовляем стоп в нужном колличеве
		elseif (val.pos_sum ~= 0  and val.stop_sum == 0) then
			message(key..": pos_sum - "..val.pos_sum..", stop_sum - "..val.stop_sum.." Add a stop order", 2);
			-- Ставим новую стоп заявку
			new_stop_order (key, val);

		-- Позиция(нет) и Стоп(есть) удаляем все стоп ордера
		elseif (val.pos_sum == 0  and val.stop_sum ~= 0) then
			message(key..": pos_sum - "..val.pos_sum..", stop_sum - "..val.stop_sum.." Removing all stop orders", 2);
			-- Удаляем стоп заявку
			kill_stop_order(key, val);
		end;

		-- Удаляем позицию по времени (В конце дня) еcли определена константа TIME_CLOSE
		if TIME_CLOSE then
			if(val.pos_sum ~= 0 and getInfoParam("LOCALTIME") >= TIME_CLOSE)  then
				message("Close on time: "..key, 2);
				-- Удаляем лиминтые ордера
				kill_all_futures_orders(key);
				-- Закрываем позицию по рынку, стоп ордера снимуться при следуюем проходе цикла
				new_order(key, val);
			end;
		end;
	end;

end;

-- Выставляем стоп ордер по инструменту.
function new_stop_order (seccode, val)
	-- Для позиции шорт - ПО УМОЛЧАНИЮ
	local operation, condition, offset, stopprice2 = "B", "5", tostring(0), val.pos_price + val.stop_indent;
	-- Для позиции лонг
	if val.pos_sum > 0 then
		operation, condition, offset, stopprice2 = "S", "4", tostring(0), val.pos_price - val.stop_indent;
	end;
	-- Если есть старая стоп заявка, берем стоп-цену из старой заявки
	if val.stop_price then stopprice2 = val.stop_price; end

	local Transaction = {
		['ACTION'] 								= "NEW_STOP_ORDER",
		['EXPIRY_DATE'] 					= "TODAY",--"GTC", -- на учебном серве только стоп-заявки с истечением сегодня, потом поменять на GTC
		['STOP_ORDER_KIND'] 			= "TAKE_PROFIT_AND_STOP_LIMIT_ORDER", -- Тип стоп-заявки
		['MARKET_STOP_LIMIT'] 		= "YES",
		['MARKET_TAKE_PROFIT'] 		= "YES",
		['TYPE'] 									= "M",
		['ACCOUNT'] 							= ACCOUNT_ID,
		['CLASSCODE'] 						= CLASS_CODE,
		['CLIENT_CODE'] 					= ACCOUNT_ID, -- Комментарий к транзакции, который будет виден в транзакциях, заявках и сделках
		['PRICE'] 								= "0", -- Цена, по которой выставится заявка при срабатывании Стоп-Лосса (для рыночной заявки по акциям должна быть 0)
		['STOPPRICE'] 						= "0", -- Цена Тэйк-Профита
		["STOPPRICE2"] 						= removeZero(stopprice2), -- Цена Стоп-Лосса
		["OFFSET"]  							= offset, -- Величина отступа от максимума (минимума) цены последней сделки.
		['TRANS_ID'] 							= removeZero(val.stop_trans_id),
		['SECCODE'] 							= seccode,
		['OPERATION'] 						= operation, -- Направление заявки, обязательный параметр. Значения: «S» – продать, «B» – купить
		['CONDITION'] 						= condition, -- Направленность стоп-цены. Возможные значения: «4» - меньше или равно, «5» – больше или равно
		['QUANTITY']  						= tostring(math.abs(val.pos_sum)), -- Количество лотов в заявке, обязательный параметр
	};

	local res = sendTransaction(Transaction);
	if res ~= "" then message('Error: '..res, 3); end;
end;

-- Закрываем позицию по маркету
function new_order (seccode, val)

	local operation = "B";
	local price = tostring(getParamEx(CLASS_CODE, seccode, "PRICEMAX").param_value);
	-- Для позиции лонг
	if val.pos_sum > 0 then
		operation = "S";
		price = tostring(getParamEx(CLASS_CODE, seccode, "PRICEMIN").param_value);
	end;

	local Transaction = {
		['ACTION'] 						= "NEW_ORDER",
		['TYPE'] 							= "M",
		['ACCOUNT'] 					= ACCOUNT_ID,
		['CLASSCODE'] 				= CLASS_CODE,
		['CLIENT_CODE'] 			= "Close on time", -- Комментарий к транзакции, который будет виден в транзакциях, заявках и сделках
		['PRICE'] 						= removeZero(price), -- Используем цену по кторой входили в позицю
		['TRANS_ID'] 					= removeZero(val.stop_trans_id),
		['SECCODE'] 					= seccode,
		['OPERATION'] 				= operation, -- Направление заявки, обязательный параметр. Значения: «S» – продать, «B» – купить
		['QUANTITY']  				= tostring(math.abs(val.pos_sum)), -- Количество лотов в заявке, обязательный параметр
	};

	local res = sendTransaction(Transaction);
	if res ~= "" then message('Error: '..res, 3); end;
end

-- Удаляем Стоп ордер по инстументу
function kill_stop_order (seccode,val)
	local Transaction = {
       ['ACTION'] 					= "KILL_STOP_ORDER",
       ['CLASSCODE'] 				= CLASS_CODE,
       ['SECCODE'] 					= seccode,
       ['ACCOUNT'] 					= ACCOUNT_ID,
       ['CLIENT_CODE'] 			= ACCOUNT_ID, -- Комментарий к транзакции, который будет виден в транзакциях, заявках и сделках
       ['TRANS_ID'] 				= removeZero(val.stop_trans_id), -- ID УДАЛЯЮЩЕЙ транзакции
       ['STOP_ORDER_KEY'] 	= tostring(val.stop_order_id)
   	};

	local res = sendTransaction(Transaction);
	if res ~= "" then message('Error: '..res, 3); end;
end;

-- Удаляем все активные лимитные заявки по иструменту
function kill_all_futures_orders (seccode)
	local Transaction = {
       ['ACTION'] 					= "KILL_ALL_FUTURES_ORDERS",
       ['CLASSCODE'] 				= CLASS_CODE,
       ['ACCOUNT'] 					= ACCOUNT_ID,
       ['CLIENT_CODE'] 			= ACCOUNT_ID, -- Комментарий к транзакции, который будет виден в транзакциях, заявках и сделках
       ['TRANS_ID'] 				= "2002",
       ['SECCODE'] 					= seccode,
       ['BASE_CONTRACT'] 		= getSecurityInfo(CLASS_CODE, seccode).base_active_seccode,
   	};
	local res = sendTransaction(Transaction);
	if res ~= "" then message('Error: '..res, 3); end;
end;
