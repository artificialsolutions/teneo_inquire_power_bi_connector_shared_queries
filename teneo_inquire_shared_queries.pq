// This file contains your Data Connector logic
[Version = "7.3.0-2"]
section teneo_inquire_shared_queries;

[DataSource.Kind="teneo_inquire_shared_queries", Publish="teneo_inquire_shared_queries.Publish"]
shared teneo_inquire_shared_queries.Contents = (url as text, lds as text) as table =>
    let
        results = Function.InvokeAfter(()=>GetResults(url, lds), #duration(0,0,0,2)),
        tableResult = Function.InvokeAfter(()=>#table({"Name", "Key", "Data", "ItemKind", "ItemName", "IsLeaf"}, results), #duration(0,0,0,2)),
        tableNav = Function.InvokeAfter(()=>Table.ToNavigationTable(tableResult, {"Key"}, "Name", "Data", "ItemKind", "ItemName", "IsLeaf"), #duration(0,0,0,2))
    in
        tableNav;

// Data Source Kind description
teneo_inquire_shared_queries = [
    Authentication = [
        UsernamePassword = []
    ]
];

// Data Source UI publishing description
teneo_inquire_shared_queries.Publish = [
    Beta = true,
    Category = "Other",
    ButtonText = { Extension.LoadString("ButtonTitle"), Extension.LoadString("ButtonHelp") },
    LearnMoreUrl = "https://developers.teneo.ai/",
    SourceImage = teneo_inquire_shared_queries.Icons,
    SourceTypeImage = teneo_inquire_shared_queries.Icons
];

teneo_inquire_shared_queries.Icons = [
    Icon16 = { Extension.Contents("teneo_inquire_shared_queries16.png"), Extension.Contents("teneo_inquire_shared_queries20.png"), Extension.Contents("teneo_inquire_shared_queries24.png"), Extension.Contents("teneo_inquire_shared_queries32.png") },
    Icon32 = { Extension.Contents("teneo_inquire_shared_queries32.png"), Extension.Contents("teneo_inquire_shared_queries40.png"), Extension.Contents("teneo_inquire_shared_queries48.png"), Extension.Contents("teneo_inquire_shared_queries64.png") }
];

authType = "Bearer ";


Table.ToNavigationTable = (
    table as table,
    keyColumns as list,
    nameColumn as text,
    dataColumn as text,
    itemKindColumn as text,
    itemNameColumn as text,
    isLeafColumn as text
) as table =>
    let
        tableType = Value.Type(table),
        newTableType = Type.AddTableKey(tableType, keyColumns, true) meta
        [
            NavigationTable.NameColumn = nameColumn,
            NavigationTable.DataColumn = dataColumn,
            NavigationTable.ItemKindColumn = itemKindColumn,
            Preview.DelayColumn = itemNameColumn,
            NavigationTable.IsLeafColumn = isLeafColumn
        ],
        navigationTable = Value.ReplaceType(table, newTableType)
    in
        navigationTable;

SubmitQuery = (url as text, lds as text, id as text, authToken as text) as record =>
    let
        postData = [query = id],
        source = Web.Contents(url, [
            RelativePath = "/tql/submit",
            Query = [timeout = "120", lds = lds],
            Content = Text.ToBinary(Uri.BuildQueryString(postData)),
            Headers = [Authorization = Text.Combine({authType, authToken}), #"Accept" = "*/*", #"Content-Type" = "application/x-www-form-urlencoded"],
            IsRetry = true,
            Timeout = #duration(1, 0, 0, 0)
        ]),
        textSource = Text.FromBinary(source)
    in
        Json.Document(textSource);

GetIds = (ar as list) as table =>
    let
        ids = Table.FromRecords(ar)
    in
        ids;

SharedQueries = (url as text, lds as text, authToken as text) as list =>
    let
        path = Text.Combine({"/tql/", lds}),
        source = Web.Contents(url, [
            RelativePath = Text.Combine({path, "/shared-queries"}),
            Headers = [Authorization = Text.Combine({authType, authToken})],
            Timeout = #duration(1, 0, 0, 0)
        ]),
        textSource = Text.FromBinary(source),
        json = Json.Document(textSource)
    in
        json;

Login = (url as text, username as text, password as text) as text =>
    let
        json = Json.FromValue([user = username, username = username, pass = password, password = password]),
        authSource = Web.Contents(url,
        [
            RelativePath = "/auth/login",
            Headers = [#"Content-Type" = "application/json"],
            Content = json
        ]
        ),
        authToken = Text.FromBinary(authSource),
        token = if Text.StartsWith(authToken, """") then Text.BetweenDelimiters(authToken, """", """") else authToken
    in
        token;

Poll = (url as text, authToken as text, queryId as text) as table =>
    let
        source = Web.Contents(url, [
            RelativePath = "/tql/poll",
            Query = [id = queryId, timeout = "120000"],
            Headers = [Authorization = Text.Combine({authType, authToken})],
            IsRetry = true,
            Timeout = #duration(1, 0, 0, 0)
        ]),
        textSource = Text.FromBinary(source),
        json = Json.Document(textSource),
        // The valid return types are final, partial, cancelled and failure
        results = if json[type] = "final" or json[type] = "FinalResultMessage" then Table.FromRecords(json[result])
            else if json[type] = "partial" or json[type] = "PartialUpdateMessage" then @Poll(url, authToken, queryId)
            else if json[type] = "cancelled" or json[type] = "CancelledQueryMessage" then error "query cancelled"
            else if json[type] = "failure" or json[type] = "FailureMessage" then error json[errorMessage]
            else error Text.Combine({"Unknown result type", json[type]})
    in
        results;


GetColumnDataType = (indata as table) as record =>
    let
        names = Table.ColumnNames(indata),
        textList = List.Select(names, each Text.StartsWith(_, "s.") or Text.StartsWith(_, "s:") or Text.StartsWith(_, "t.e.") or Text.StartsWith(_, "s.sv:")),
        dateList = List.Select(names, each Text.StartsWith(_, "d.") or Text.StartsWith(_, "d:")),
        dateTimeList = List.Select(names, each Text.StartsWith(_, "dt.") or Text.StartsWith(_, "dt:") or Text.StartsWith(_, "date")),
        timeList = List.Select(names, each Text.StartsWith(_, "t:")),
        logicalList = List.Select(names, each Text.StartsWith(_, "l.") or Text.StartsWith(_, "l:")),
        binaryList = List.Select(names, each Text.StartsWith(_, "b.") or Text.StartsWith(_, "b:")),
        floatList = List.Select(names, each Text.StartsWith(_, "f.") or Text.StartsWith(_, "f:")),
        integerList = List.Select(names, each Text.StartsWith(_, "n.") or Text.StartsWith(_, "n:") or Text.StartsWith(_, "count"))
    in
        [text = textList, date = dateList, datetime = dateTimeList, time = timeList, logical = logicalList, binary = binaryList, float = floatList, integer = integerList];


SetColumnNames = (indata as table) as table =>
    let
        columnNames = Table.ColumnNames(indata),
        newColumnNames = List.Transform(columnNames, each {_, Text.AfterDelimiter(_, ":")}),
        outdata = Table.RenameColumns(indata, newColumnNames)
    in
        outdata;


SetColumnData = (types as record, indata as table) as table =>
    let
        textTable = Table.TransformColumns(indata, List.Transform(types[text], each {_, each _, Text.Type})),
        dateTable = Table.TransformColumns(textTable, List.Transform(types[date], each {_, each Date.FromText(_), Date.Type})),
        dateTimeTable = Table.TransformColumns(dateTable, List.Transform(types[datetime], each {_, each DateTime.FromText(_), DateTime.Type})),
        timeTable = Table.TransformColumns(dateTimeTable, List.Transform(types[time], each {_, each Time.FromText(_), Time.Type})),
        logicalTable = Table.TransformColumns(timeTable, List.Transform(types[logical], each {_, each Logical.FromText(_), Logical.Type})),
        binaryTable = Table.TransformColumns(logicalTable, List.Transform(types[binary], each {_, each Binary.FromText(_), Binary.Type})),
        floatTable = Table.TransformColumns(binaryTable, List.Transform(types[float], each {_, each _,  Number.Type})),
        integerTable = Table.TransformColumns(floatTable, List.Transform(types[integer], each {_, each _,  Int64.Type})),
        finalTable = SetColumnNames(integerTable)
    in
        finalTable;


GetData = (url as text, authToken as text, queryId as text) as table =>
    let
        polledData = Function.InvokeAfter(()=>Poll(url, authToken, queryId), #duration(0,0,0,2)),
        columnType = Function.InvokeAfter(()=>GetColumnDataType(polledData), #duration(0,0,0,2)),
        data = Function.InvokeAfter(()=>SetColumnData(columnType, polledData), #duration(0,0,0,2))
    in
        data;

GetResults = (url as text, lds as text) as list =>
    let
        authToken = Login(url, Extension.CurrentCredential()[Username], Extension.CurrentCredential()[Password]),
        sharedQueriesList = SharedQueries(url, lds, authToken),
        queries = Table.FromRecords(sharedQueriesList),
        submittedIds = Table.FromRecords(List.Generate(()=> [i = 0, index = 0, y=SubmitQuery(url, lds, queries[query]{i}, authToken)], each [index]< List.Count(queries[id]), each [index=[index] + 1, i = [i] + 1, y=SubmitQuery(url, lds, queries[query]{i}, authToken)], each [y]))[id],
        results = List.Generate(
            ()=> [index = 0, y={queries[publishedName]{0}, queries[publishedName]{0}, GetData(url, authToken, submittedIds{0}), "Table", "Table", true}],
            each [index]< List.Count(submittedIds),
            each [index=[index] + 1, y={queries[publishedName]{index}, queries[publishedName]{index}, GetData(url, authToken, submittedIds{index}), "Table", "Table", true}],
            each [y]
        )
    in
        results;
