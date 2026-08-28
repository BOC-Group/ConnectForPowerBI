[Version = "1.0.0"]
section BOCADONISADOITConnector;

// Helper function to create navigation tables
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
            NavigationTable.IsLeafColumn = isLeafColumn,
            Preview.DelayColumn = itemNameColumn
        ],
        navigationTable = Value.ReplaceType(table, newTableType)
    in
        navigationTable;

BOCADONISADOITConnector.ContentsType = type function (
    baseUrl as (type text meta [
        Documentation.FieldCaption = "Base URL",
        Documentation.FieldDescription = "Base URL of the ADONIS or ADOIT installation, for example https://example.com/ADOIT/.",
        Documentation.SampleValues = {"https://example.com/ADOIT/"}
    ]),
    optional client_id as (type text meta [
        DataSource.Path = true,
        Documentation.FieldCaption = "Client ID (defaults to PowerBIID)",
        Documentation.FieldDescription = "OAuth public-client ID. Leave empty to use PowerBIID.",
        Documentation.SampleValues = {"PowerBIID"}
    ]),
    // Deliberately not part of the data source path: switching language must
    // reuse the existing credential instead of prompting for a new sign-in.
    optional language as (type text meta [
        DataSource.Path = false,
        Documentation.FieldCaption = "Language",
        Documentation.FieldDescription = "Language used for attribute values and metamodel labels. Defaults to English.",
        Documentation.AllowedValues = {"en", "de", "es", "fr"}
    ])
) as any;

[DataSource.Kind="BOCADONISADOITConnector", Publish="BOCADONISADOITConnector.Publish"]
shared BOCADONISADOITConnector.Contents = Value.ReplaceType(BOCADONISADOITConnector.ContentsImpl, BOCADONISADOITConnector.ContentsType);

BOCADONISADOITConnector.ContentsImpl = (baseUrl as text, optional client_id as text, optional language as text) =>
    let
        baseUrlWithSlash = if Text.EndsWith(baseUrl, "/") then baseUrl else baseUrl & "/",
        effectiveLanguage = NormalizeLanguage(language),

        // Create the navigation table
        repoList = GetReposList(baseUrlWithSlash, effectiveLanguage),
        relationAndAttributeNames = RelationAndAttributeNamesNavigationTable(baseUrlWithSlash, effectiveLanguage),
        
        // Create the base navigation table
        objects = #table(
            {"Name", "Key", "Data", "ItemKind", "ItemName", "IsLeaf"},
            {
                {"Repositories", "repos", repoList, "Folder", "Folder", false},
                {"Relation and Attribute Names", "metamodel_names", relationAndAttributeNames, "Folder", "Folder", false},
                {"Functions", "functions", FunctionsNavigationTable(baseUrlWithSlash, effectiveLanguage), "Folder", "Folder", false}
            }
        ),
        NavTable = Table.ToNavigationTable(objects, {"Key"}, "Name", "Data", "ItemKind", "ItemName", "IsLeaf"),
        
        // Also expose the API functions for backwards compatibility
        result = Value.ReplaceMetadata(NavTable, [
            GetObject = (objectName as text, langIndependantAttributes as list, langDependantAttributes as list, optional repositoryId as text) =>
                getObject(baseUrlWithSlash, effectiveLanguage, objectName, langIndependantAttributes, langDependantAttributes, repositoryId),
            GetObjectWithName = (objectName as text, langIndependentAttributes as list, langDependentAttributes as list, optional repositoryId as text) =>
                getObjectWithName(baseUrlWithSlash, effectiveLanguage, objectName, langIndependentAttributes, langDependentAttributes, repositoryId),
            GetObjectWithNameDelimiter = (objectName as text, langIndependentAttributes as list, langDependentAttributes as list, delimiter, optional repositoryId as text) =>
                getObjectWithNameDelimiter(baseUrlWithSlash, effectiveLanguage, objectName, langIndependentAttributes, langDependentAttributes, delimiter, repositoryId),
            GetObjectWithType = (objectName as text, langIndependentAttributes as list, langDependentAttributes as list, optional repositoryId as text) =>
                getObjectWithType(baseUrlWithSlash, effectiveLanguage, objectName, langIndependentAttributes, langDependentAttributes, repositoryId),
            GetObjectWithAttributes = GetObjectWithAttributesFunction(baseUrlWithSlash, effectiveLanguage),
            GetRelationTable = (objectA as text, relationName as text, objectB as text, optional repositoryId as text) =>
                getRelationTable(baseUrlWithSlash, effectiveLanguage, objectA, relationName, objectB, repositoryId),
            GetRelationTableIncoming = (objectA as text, relationName as text, objectB as text, optional repositoryId as text) =>
                getRelationTableIncoming(baseUrlWithSlash, effectiveLanguage, objectA, relationName, objectB, repositoryId),
            GetRelationTableOutgoing = (objectA as text, relationName as text, objectB as text, optional repositoryId as text) =>
                getRelationTableOutgoing(baseUrlWithSlash, effectiveLanguage, objectA, relationName, objectB, repositoryId),
            GetCustomClassFunction = GetCustomClassFunction(baseUrlWithSlash, effectiveLanguage),
            GetCustomRelationFunction = GetCustomRelationFunction(baseUrlWithSlash, effectiveLanguage),
            GetAvailableRepositories = GetAvailableRepositoriesFunction(baseUrlWithSlash, effectiveLanguage),
            ListSavedSearches = GetSavedSearchesFunction(baseUrlWithSlash, effectiveLanguage),
            ExecuteSavedSearch = GetExecuteSavedSearchFunction(baseUrlWithSlash, effectiveLanguage),
            GetAvailableClasses = GetAvailableClassesFunction(baseUrlWithSlash, effectiveLanguage),
            GetClassAttributes = GetClassAttributesFunction(baseUrlWithSlash, effectiveLanguage),
            GetClassRelations = GetClassRelationsFunction(baseUrlWithSlash, effectiveLanguage)
        ])
    in
        result;

// Get list of repositories
GetReposList = (baseUrl as text, language as text) =>
    let
        reposResponse = getRequest(baseUrl, language, getBaseURL(baseUrl) & "repos/"),
        repos = reposResponse[repos],
        repoTable = Table.FromList(repos, Splitter.SplitByNothing(), null, null, ExtraValues.Error),
        expandedRepos = Table.ExpandRecordColumn(repoTable, "Column1", {"id", "name"}, {"RepoID", "RepoName"}),
        
        // Create navigation entries for each repo
        repoEntries = List.Transform(
            Table.ToRecords(expandedRepos),
            (repo) => {
                repo[RepoName],
                repo[RepoID],
                ObjectsInRepoNavigationTable(baseUrl, language, repo[RepoID], repo[RepoName]),
                "Folder",
                "Folder",
                false
            }
        ),
        
        // Create the navigation table
        navTable = #table(
            {"Name", "Key", "Data", "ItemKind", "ItemName", "IsLeaf"},
            repoEntries
        ),
        result = Table.ToNavigationTable(navTable, {"Key"}, "Name", "Data", "ItemKind", "ItemName", "IsLeaf")
    in
        result;

// Get objects for a specific repository
ObjectsInRepoNavigationTable = (baseUrl as text, language as text, repoId as text, repoName as text) =>
    let
        dynamicClasses = GetDynamicObjectClassRows(baseUrl, language, repoId),
        result = Table.ToNavigationTable(dynamicClasses, {"Key"}, "Name", "Data", "ItemKind", "ItemName", "IsLeaf")
    in
        result;

// Prefer a localized metamodel label. Older installations may only expose a
// technical name, so turn names such as C_APPLICATION_COMPONENT into
// "Application Component" as a final fallback.
// Supported ISO 639-1 codes for the Accept-Language header and for picking a
// translation out of a metamodel displayNames record.
default_language = "en";
supported_languages = {"en", "de", "es", "fr"};

// An unset or unrecognised value falls back to English rather than failing, so
// an existing report keeps refreshing if it was built before this option
// existed or if it stored a language the installation no longer offers.
NormalizeLanguage = (language as nullable text) as text =>
    let
        trimmed = if language = null then "" else Text.Lower(Text.Trim(language)),
        result = if List.Contains(supported_languages, trimmed) then trimmed else default_language
    in
        result;

// The metamodel endpoints do not accept Accept-Language. They return every
// translation at once in a displayNames record, so the label for the selected
// language is picked on the client. Fall back to English, then to whatever
// translation the installation actually ships.
PickDisplayName = (displayNames as any, language as text) as nullable text =>
    let
        isRecord = Value.Is(displayNames, type record),
        preferred = if isRecord then Record.FieldOrDefault(displayNames, language, null) else null,
        english = if isRecord then Record.FieldOrDefault(displayNames, "en", null) else null,
        anyLocalized =
            if isRecord
            then List.First(
                List.Select(
                    Record.FieldValues(displayNames),
                    each Value.Is(_, type text) and Text.Trim(_) <> ""
                ),
                null
            )
            else null,
        candidates = List.Select(
            {preferred, english, anyLocalized},
            each Value.Is(_, type text) and Text.Trim(_) <> ""
        )
    in
        List.First(candidates, null);

GetHumanReadableClassName = (classRecord as record, fallbackMetaName as text, language as text) as text =>
    let
        displayNames = Record.FieldOrDefault(classRecord, "displayNames", null),
        localizedDisplayName = PickDisplayName(displayNames, language),
        displayName = Record.FieldOrDefault(classRecord, "displayName", null),
        configuredName = Record.FieldOrDefault(classRecord, "name", null),
        candidates = List.Select(
            {localizedDisplayName, displayName, configuredName},
            each Value.Is(_, type text) and Text.Trim(_) <> ""
        ),
        metamodelName = List.First(candidates, null),
        looksTechnical =
            metamodelName = null or
            metamodelName = fallbackMetaName or
            (Text.StartsWith(metamodelName, "C_") and Text.Upper(metamodelName) = metamodelName),
        fallbackWithoutPrefix =
            if Text.StartsWith(fallbackMetaName, "C_")
            then Text.Range(fallbackMetaName, 2)
            else fallbackMetaName,
        readableFallback = Text.Proper(Text.Replace(fallbackWithoutPrefix, "_", " ")),
        result = if looksTechnical then readableFallback else Text.Trim(metamodelName)
    in
        result;

// Generate a copy-ready example that refers to the function name shown in the
// Navigator rather than to an internal connector implementation function.
GetLoadClassExample = (classMetaName as text, attributesAndRelations as text) as text =>
    "#""Load Class by Technical Name""(""" & classMetaName & """, """ & attributesAndRelations & """)";

// REST 4 exposes class lookup as a collection endpoint without a name query
// parameter. Resolve technical names locally so products that ignore unknown
// query parameters cannot accidentally return the first class in the list.
// Support both spellings seen in REST responses across product generations.
GetClassMetaName = (classRecord as record) as nullable text =>
    let
        candidates = List.Select(
            {
                Record.FieldOrDefault(classRecord, "metaName", null),
                Record.FieldOrDefault(classRecord, "metaname", null)
            },
            each Value.Is(_, type text) and Text.Trim(_) <> ""
        )
    in
        List.First(candidates, null);

ResolveClassByMetaName = (baseUrl as text, language as text, className as text) as nullable record =>
    let
        classesResponse = getRequest(baseUrl, language, getBaseURL(baseUrl) & "metamodel/classes/"),
        classesValue = Record.FieldOrDefault(classesResponse, "classes", {}),
        classes =
            if Value.Is(classesValue, type list)
            then List.Select(classesValue, each Value.Is(_, type record))
            else {},
        requestedName = Text.Upper(Text.Trim(className)),
        matches = List.Select(
            classes,
            each
                let
                    metaName = GetClassMetaName(_)
                in
                    metaName <> null and Text.Upper(metaName) = requestedName
        )
    in
        List.First(matches, null);

// Only expose metamodel classes intended for end-user selection.
IsVisibleConcreteClass = (classRecord as record) as logical =>
    let
        isVisible = Record.FieldOrDefault(classRecord, "visible", false) = true,
        isAbstract = Record.FieldOrDefault(classRecord, "abstract", true) = true,
        hasIdentity =
            GetClassMetaName(classRecord) <> null and
            Record.FieldOrDefault(classRecord, "id", null) <> null
    in
        isVisible and not isAbstract and hasIdentity;

// Build navigation rows from the classes configured in the customer's metamodel.
GetDynamicObjectClassRows = (baseUrl as text, language as text, repoId as text) as table =>
    let
        classesResponse = getRequest(baseUrl, language, getBaseURL(baseUrl) & "metamodel/classes/"),
        classes = Record.FieldOrDefault(classesResponse, "classes", {}),
        concreteClasses = List.Select(classes, each IsVisibleConcreteClass(_)),
        classEntries = List.Transform(
            concreteClasses,
            (classRecord as record) =>
                let
                    metaName = Text.From(GetClassMetaName(classRecord)),
                    displayName = GetHumanReadableClassName(classRecord, metaName, language)
                in
                    {
                        displayName,
                        metaName & "_" & repoId,
                        GetClassFieldSelectionFunction(baseUrl, language, metaName, displayName, repoId),
                        "Function",
                        "Function",
                        true
                    }
        ),
        classTable = #table(
            {"Name", "Key", "Data", "ItemKind", "ItemName", "IsLeaf"},
            classEntries
        ),
        result = Table.Sort(classTable, {{"Name", Order.Ascending}})
    in
        result;

// Recursively flatten notebook chapters because customers can nest attribute groups.
FlattenNotebookNodes = (nodes as list) as list =>
    List.Combine(
        List.Transform(
            nodes,
            (node as record) =>
                let
                    children = Record.FieldOrDefault(node, "children", {}),
                    descendants = if Value.Is(children, type list) then @FlattenNotebookNodes(children) else {}
                in
                    {node} & descendants
        )
    );

ParseCommaSeparatedNames = (value as nullable text) as list =>
    if value = null
    then {}
    else
        List.Distinct(
            List.Select(
                List.Transform(Text.Split(value, ","), each Text.Trim(_)),
                each _ <> ""
            )
        );

// Repository class leaves are functions so the requested field list remains
// visible and editable in the generated M query.
GetClassFieldSelectionFunction = (baseUrl as text, language as text, objectClassName as text, displayName as text, repoId as text) as function =>
    let
        implementation = (optional attributesAndRelations as nullable text) as table =>
            let
                requestedFields = List.Distinct({"NAME"} & ParseCommaSeparatedNames(attributesAndRelations)),
                objects = getObjectWithNameDelimiter(baseUrl, language, objectClassName, requestedFields, {}, "; ", repoId),
                result =
                    if Table.IsEmpty(objects)
                    then #table(
                        {"Information"},
                        {{"No objects of class '" & displayName & "' were found in repository '" & repoId & "'."}}
                    )
                    else objects
            in
                result,
        functionType = type function (
            optional attributesAndRelations as (type nullable text meta [
                Documentation.FieldCaption = "Attributes and relations (comma-separated)",
                Documentation.FieldDescription = "Optional comma-separated technical names to load. Leave empty to load only NAME and ID.",
                Documentation.SampleValues = {"A_DESCRIPTION, A_VALID_FROM, RC_REALIZATION"}
            ])
        ) as table,
        result = Value.ReplaceType(implementation, functionType)
    in
        result;

// Add one mapping table per class so report authors can discover the technical
// attribute and relation names required by the custom query functions.
RelationAndAttributeNamesNavigationTable = (baseUrl as text, language as text) as table =>
    let
        classesResponse = getRequest(baseUrl, language, getBaseURL(baseUrl) & "metamodel/classes/"),
        classes = Record.FieldOrDefault(classesResponse, "classes", {}),
        concreteClasses = List.Select(classes, each IsVisibleConcreteClass(_)),
        classEntries = List.Transform(
            concreteClasses,
            (classRecord as record) =>
                let
                    classId = Text.From(classRecord[id]),
                    metaName = Text.From(GetClassMetaName(classRecord)),
                    displayName = GetHumanReadableClassName(classRecord, metaName, language)
                in
                    {
                        displayName & " - A/R",
                        "metamodel_names_" & metaName,
                        GetClassRelationAndAttributeNames(baseUrl, language, classId, metaName),
                        "Table",
                        "Table",
                        true
                    }
        ),
        classTable = #table(
            {"Name", "Key", "Data", "ItemKind", "ItemName", "IsLeaf"},
            classEntries
        ),
        sortedTable = Table.Sort(classTable, {{"Name", Order.Ascending}}),
        result = Table.ToNavigationTable(sortedTable, {"Key"}, "Name", "Data", "ItemKind", "ItemName", "IsLeaf")
    in
        result;

GetClassRelationAndAttributeNames = (baseUrl as text, language as text, classId as text, classMetaName as text) as table =>
    let
        notebookResponse = try getRequest(baseUrl, language, getBaseURL(baseUrl) & "metamodel/classes/" & classId & "/notebook/") otherwise [chapters = {}],
        chapters = Record.FieldOrDefault(notebookResponse, "chapters", {}),
        notebookNodes = if Value.Is(chapters, type list) then FlattenNotebookNodes(chapters) else {},
        notebookItems = List.Select(
            notebookNodes,
            each
                let
                    metaName = Record.FieldOrDefault(_, "metaname", Record.FieldOrDefault(_, "metaName", null)),
                    isAttribute = Record.HasFields(_, "attrType"),
                    isRelation = Record.HasFields(_, "relClass")
                in
                    Value.Is(metaName, type text) and
                    Text.Trim(metaName) <> "" and
                    (isAttribute or isRelation)
        ),
        notebookRows = List.Transform(
            notebookItems,
            each
                let
                    metaName = Text.From(Record.FieldOrDefault(_, "metaname", Record.FieldOrDefault(_, "metaName", ""))),
                    kind = if Record.HasFields(_, "relClass") then "Relation" else "Attribute"
                in
                    {
                        kind,
                        metaName,
                        GetHumanReadableClassName(_, metaName, language),
                        GetLoadClassExample(classMetaName, metaName)
                    }
        ),
        mappingTable = #table(
            {"Kind", "Technical Name", "Display Name", "Example Usage"},
            notebookRows
        ),
        distinctMappings = Table.Distinct(mappingTable, {"Kind", "Technical Name"}),
        result = Table.Sort(distinctMappings, {{"Kind", Order.Ascending}, {"Display Name", Order.Ascending}})
    in
        result;

// Create a navigation table for functions
FunctionsNavigationTable = (baseUrl as text, language as text) =>
    let
        // Create a navigation table with helper functions
        functions = #table(
            {"Name", "Key", "Data", "ItemKind", "ItemName", "IsLeaf"},
            {
                {"Load Class by Technical Name", "load_class", GetGenericClassFunction(baseUrl, language), "Function", "Function", true},
                {"Load Relation Table", "load_relation", GetEndUserRelationFunction(baseUrl, language), "Function", "Function", true},
                {"List Available Repositories", "available_repositories", GetAvailableRepositoriesFunction(baseUrl, language), "Function", "Function", true},
                {"List Saved Searches", "saved_searches", GetSavedSearchesFunction(baseUrl, language), "Function", "Function", true},
                {"Execute Saved Search", "execute_saved_search", GetExecuteSavedSearchFunction(baseUrl, language), "Function", "Function", true},
                {"List Available Classes", "available_classes", GetAvailableClassesFunction(baseUrl, language), "Function", "Function", true},
                {"List Class Notebook A/R", "class_notebook_fields", GetClassNotebookFieldsFunction(baseUrl, language), "Function", "Function", true}
            }
        ),
        
        result = Table.ToNavigationTable(functions, {"Key"}, "Name", "Data", "ItemKind", "ItemName", "IsLeaf")
    in
        result;

// Generic class loader for technical or hidden classes that are not exposed
// beneath a repository in the Navigator.
GetGenericClassFunction = (baseUrl as text, language as text) as function =>
    let
        implementation = (className as text, optional attributesAndRelations as nullable text, optional repositoryId as text) as table =>
            let
                effectiveRepoId =
                    if repositoryId = null or Text.Trim(repositoryId) = ""
                    then getRepoID(baseUrl, language, 1)
                    else repositoryId,
                loader = GetClassFieldSelectionFunction(baseUrl, language, className, className, effectiveRepoId),
                result = loader(attributesAndRelations)
            in
                result,
        functionType = type function (
            className as (type text meta [
                Documentation.FieldCaption = "Technical class name",
                Documentation.SampleValues = {"C_APPLICATION_COMPONENT"}
            ]),
            optional attributesAndRelations as (type nullable text meta [
                Documentation.FieldCaption = "Attributes and relations (comma-separated)",
                Documentation.FieldDescription = "Leave empty to load only NAME and ID.",
                Documentation.SampleValues = {"A_DESCRIPTION, A_VALID_FROM, RC_REALIZATION"}
            ]),
            optional repositoryId as (type text meta [
                Documentation.FieldCaption = "Repository ID",
                Documentation.FieldDescription = "Leave empty to use the first available repository."
            ])
        ) as table,
        result = Value.ReplaceType(implementation, functionType)
    in
        result;

// Human-readable wrapper around the generic relation builder.
GetEndUserRelationFunction = (baseUrl as text, language as text) as function =>
    let
        implementation = GetCustomRelationFunction(baseUrl, language),
        functionType = type function (
            sourceClass as (type text meta [
                Documentation.FieldCaption = "Source class (technical name)",
                Documentation.SampleValues = {"C_APPLICATION_COMPONENT"}
            ]),
            relationName as (type text meta [
                Documentation.FieldCaption = "Relation (technical name)",
                Documentation.SampleValues = {"RC_IS_APPLICATION_OWNER"}
            ]),
            targetClass as (type text meta [
                Documentation.FieldCaption = "Target class (technical name)",
                Documentation.SampleValues = {"C_BUSINESS_ACTOR"}
            ]),
            optional direction as (type text meta [
                Documentation.FieldCaption = "Direction",
                Documentation.FieldDescription = "Which way the relation is followed, from the source class to the target class. OUTGOING keeps relations that point from the source to the target, INCOMING keeps those pointing back, and BOTH applies no direction filter. Leave empty to use BOTH.",
                Documentation.AllowedValues = {"BOTH", "INCOMING", "OUTGOING"}
            ]),
            optional repositoryId as (type text meta [
                Documentation.FieldCaption = "Repository ID",
                Documentation.FieldDescription = "Leave empty to use the first available repository."
            ])
        ) as table,
        result = Value.ReplaceType(implementation, functionType)
    in
        result;

// Resolve a technical class name and return the same recursively parsed
// notebook fields used by the A/R mapping tables.
GetClassNotebookFieldsFunction = (baseUrl as text, language as text) as function =>
    let
        implementation = (className as text) as table =>
            let
                classRecord = try ResolveClassByMetaName(baseUrl, language, className) otherwise null,
                result =
                    if classRecord = null
                    then #table({"Message"}, {{"Class '" & className & "' was not found."}})
                    else
                        let
                            resolvedMetaNameValue = GetClassMetaName(classRecord),
                            resolvedMetaName = if resolvedMetaNameValue = null then className else resolvedMetaNameValue
                        in
                            GetClassRelationAndAttributeNames(baseUrl, language, Text.From(classRecord[id]), resolvedMetaName)
            in
                result,
        functionType = type function (
            className as (type text meta [
                Documentation.FieldCaption = "Technical class name",
                Documentation.SampleValues = {"C_APPLICATION_COMPONENT"}
            ])
        ) as table,
        result = Value.ReplaceType(implementation, functionType)
    in
        result;

// Return repository IDs exactly as expected by the repository-scoped loader
// functions, together with their readable names.
GetAvailableRepositoriesFunction = (baseUrl as text, language as text) as function =>
    () as table =>
        let
            reposResponse = getRequest(baseUrl, language, getBaseURL(baseUrl) & "repos/"),
            reposValue = Record.FieldOrDefault(reposResponse, "repos", {}),
            repos = if Value.Is(reposValue, type list) then reposValue else {},
            reposTable = Table.FromList(repos, Splitter.SplitByNothing(), {"Repository"}, null, ExtraValues.Error),
            expandedRepos = Table.ExpandRecordColumn(reposTable, "Repository", {"id", "name"}, {"Repository ID", "Repository Name"}),
            result = Table.Sort(expandedRepos, {{"Repository Name", Order.Ascending}})
        in
            result;

GetSavedSearchesFunction = (baseUrl as text, language as text) as function =>
    let
        implementation = (optional repositoryId as text, optional scope as text) as table =>
            let
                effectiveRepoId =
                    if repositoryId = null or Text.Trim(repositoryId) = ""
                    then getRepoID(baseUrl, language, 1)
                    else repositoryId,
                effectiveScope = if scope = null or Text.Trim(scope) = "" then "ALL" else Text.Upper(Text.Trim(scope)),
                validScopes = {"ALL", "OWN", "PUBLISHED"},
                savedSearchResponse =
                    if not List.Contains(validScopes, effectiveScope)
                    then error Error.Record(
                        "Saved Search Error",
                        "Scope must be ALL, OWN, or PUBLISHED.",
                        [Scope = effectiveScope]
                    )
                    else
                        Json.Document(
                            Web.Contents(baseUrl, [
                                Headers = [#"Accept-Language" = language],
                                RelativePath = "rest/4.0/repos/" & effectiveRepoId & "/search/saved-queries",
                                Query = [scope = effectiveScope]
                            ])
                        ),
                itemsValue = Record.FieldOrDefault(savedSearchResponse, "items", {}),
                items = if Value.Is(itemsValue, type list) then itemsValue else {},
                rows = List.Transform(
                    List.Select(items, each Value.Is(_, type record)),
                    each [
                        #"Repository ID" = effectiveRepoId,
                        #"Saved Search ID" = Record.FieldOrDefault(_, "id", null),
                        Name = Record.FieldOrDefault(_, "name", null),
                        Description = Record.FieldOrDefault(_, "description", null),
                        #"Owner ID" = Record.FieldOrDefault(_, "ownerId", null),
                        #"Owner Name" = Record.FieldOrDefault(_, "ownerName", null),
                        Published = Record.FieldOrDefault(_, "published", null)
                    ]
                ),
                columns = {"Repository ID", "Saved Search ID", "Name", "Description", "Owner ID", "Owner Name", "Published"},
                savedSearches = Table.FromRecords(rows, columns, MissingField.UseNull),
                result = Table.Sort(savedSearches, {{"Name", Order.Ascending}})
            in
                result,
        functionType = type function (
            optional repositoryId as (type text meta [
                Documentation.FieldCaption = "Repository ID",
                Documentation.FieldDescription = "Leave empty to use the first available repository."
            ]),
            optional scope as (type text meta [
                Documentation.FieldCaption = "Scope",
                Documentation.FieldDescription = "ALL returns owned and published searches.",
                Documentation.AllowedValues = {"ALL", "OWN", "PUBLISHED"}
            ])
        ) as table,
        result = Value.ReplaceType(implementation, functionType)
    in
        result;

NormalizeSavedSearchId = (queryId as text) as text =>
    let
        trimmedId = Text.Trim(queryId),
        result =
            if Text.Length(trimmedId) >= 2 and Text.StartsWith(trimmedId, "{") and Text.EndsWith(trimmedId, "}")
            then Text.Middle(trimmedId, 1, Text.Length(trimmedId) - 2)
            else trimmedId
    in
        result;

// REST 4 search results report relations next to attributes. Merge both lists,
// discard null/non-record placeholders, and pad every entry to the fields the
// shared processor expands.
NormalizeSearchItem = (item as record) as record =>
    let
        attributesValue = Record.FieldOrDefault(item, "attributes", {}),
        attributes = if Value.Is(attributesValue, type list) then attributesValue else {},
        relationsValue = Record.FieldOrDefault(item, "relations", {}),
        relations = if Value.Is(relationsValue, type list) then relationsValue else {},
        searchFields = List.Transform(
            List.Select(attributes & relations, each Value.Is(_, type record)),
            each Record.SelectFields(_, {"name", "metaName", "attrType", "value", "targets"}, MissingField.UseNull)
        ),
        identity = Record.SelectFields(
            item,
            {"rest_links", "id", "name", "type", "artefactType", "metaName", "link", "icon"},
            MissingField.UseNull
        ),
        result = identity & [attributes = searchFields]
    in
        result;

ExecuteSavedSearchPaged = (
    baseUrl as text,
    language as text,
    queryId as text,
    optional repositoryId as text,
    optional attributes as text,
    optional relations as text,
    optional includeSavedAttributes as logical
) as table =>
    let
        effectiveRepoId =
            if repositoryId = null or Text.Trim(repositoryId) = ""
            then getRepoID(baseUrl, language, 1)
            else repositoryId,
        normalizedQueryId = NormalizeSavedSearchId(queryId),
        validatedQueryId =
            if normalizedQueryId = ""
            then error Error.Record(
                "Saved Search Error",
                "Enter a saved search ID. Use List Saved Searches to find one.",
                null
            )
            else normalizedQueryId,
        // Request NAME explicitly so the object name arrives as a regular
        // attribute column, exactly as it does for the object search.
        extraAttributes = List.Distinct({"NAME"} & ParseCommaSeparatedNames(attributes)),
        extraRelations = ParseCommaSeparatedNames(relations),
        includeSaved = if includeSavedAttributes = null then true else includeSavedAttributes,
        endpoint =
            "rest/4.0/repos/" & effectiveRepoId &
            "/search/saved-queries/" & Uri.EscapeDataString(validatedQueryId),
        getPage = (rangeStart as number, rangeEnd as number) as record =>
            let
                queryParts =
                    {
                        "range-start=" & Text.From(rangeStart),
                        "range-end=" & Text.From(rangeEnd),
                        "saved-attributes=" & (if includeSaved then "true" else "false")
                    } &
                    List.Transform(extraAttributes, each "attribute=" & Uri.EscapeDataString(_)) &
                    List.Transform(extraRelations, each "relation=" & Uri.EscapeDataString(_)),
                response = Json.Document(
                    Web.Contents(baseUrl, [
                        Headers = [
                            Accept = "application/json",
                            #"Accept-Language" = language
                        ],
                        RelativePath = endpoint & "?" & Text.Combine(queryParts, "&")
                    ])
                )
            in
                response,
        firstPage = getPage(0, searchRequestStepSize - 1),
        firstItemsValue = Record.FieldOrDefault(firstPage, "items", {}),
        firstItems = if Value.Is(firstItemsValue, type list) then firstItemsValue else {},
        reportedTotal = try Number.From(Record.FieldOrDefault(firstPage, "hitsTotal", null)) otherwise null,
        totalAmount =
            if reportedTotal = null
            then List.Count(firstItems)
            else List.Max({0, Number.RoundDown(reportedTotal)}),
        remainingPageCount =
            if totalAmount <= searchRequestStepSize
            then 0
            else Number.RoundUp((totalAmount - searchRequestStepSize) / searchRequestStepSize),
        remainingPageStarts = List.Numbers(
            searchRequestStepSize,
            remainingPageCount,
            searchRequestStepSize
        ),
        remainingPages = List.Transform(
            remainingPageStarts,
            each
                let
                    pageEnd = List.Min({_ + searchRequestStepSize - 1, totalAmount - 1}),
                    page = getPage(_, pageEnd),
                    pageItemsValue = Record.FieldOrDefault(page, "items", {})
                in
                    if Value.Is(pageItemsValue, type list) then pageItemsValue else {}
        ),
        allItems = List.Buffer(List.Combine({firstItems} & remainingPages)),
        normalizedItems = List.Transform(
            List.Select(allItems, each Value.Is(_, type record)),
            each NormalizeSearchItem(_)
        ),
        result = ProcessSearchItems(normalizedItems, extraAttributes, {}, "WITH_TYPE_NAME_DELIMITER", "; ")
    in
        result;

GetExecuteSavedSearchFunction = (baseUrl as text, language as text) as function =>
    let
        implementation = (
            queryId as text,
            optional repositoryId as text,
            optional attributes as text,
            optional relations as text,
            optional includeSavedAttributes as logical
        ) as table =>
            ExecuteSavedSearchPaged(
                baseUrl,
                language,
                queryId,
                repositoryId,
                attributes,
                relations,
                includeSavedAttributes
            ),
        functionType = type function (
            queryId as (type text meta [
                Documentation.FieldCaption = "Saved search ID",
                Documentation.FieldDescription = "Copy the Saved Search ID column from List Saved Searches. Surrounding curly brackets are removed automatically.",
                Documentation.SampleValues = {"b1e7a5c3-9d24-4f18-8a6e-3c72d0f41b95"}
            ]),
            optional repositoryId as (type text meta [
                Documentation.FieldCaption = "Repository ID",
                Documentation.FieldDescription = "Leave empty to use the first available repository."
            ]),
            optional attributes as (type text meta [
                Documentation.FieldCaption = "Additional attributes (comma-separated)",
                Documentation.FieldDescription = "Technical attribute names to load on top of the saved-query columns. NAME is always included and ID is added automatically. Copy the names from the matching Class - A/R table.",
                Documentation.SampleValues = {"A_DESCRIPTION, A_VALID_FROM"}
            ]),
            optional relations as (type text meta [
                Documentation.FieldCaption = "Additional relations (comma-separated)",
                Documentation.FieldDescription = "Technical relation names to load on top of the saved-query columns. Multiple targets are combined into one cell.",
                Documentation.SampleValues = {"RC_IS_APPLICATION_OWNER, RC_REALIZATION"}
            ]),
            optional includeSavedAttributes as (type logical meta [
                Documentation.FieldCaption = "Include saved-query columns",
                Documentation.FieldDescription = "True keeps the columns the saved search itself selects. Set it to false to load only the attributes and relations entered above. Defaults to true.",
                Documentation.AllowedValues = {true, false}
            ])
        ) as table,
        result = Value.ReplaceType(implementation, functionType)
    in
        result;

// Function to get a custom class
GetCustomClassFunction = (baseUrl as text, language as text) =>
    (className as text, optional attributes as list, optional repositoryId as text) =>
        let
            langIndAttr = if attributes = null then {"NAME"} else attributes,
            result = getObjectWithType(baseUrl, language, className, langIndAttr, {}, repositoryId)
        in
            result;

// Function to build a custom relation
GetCustomRelationFunction = (baseUrl as text, language as text) =>
    (sourceClass as text, relationName as text, targetClass as text, optional direction as text, optional repositoryId as text) =>
        let
            dir = if direction = null then "BOTH" else direction,
            result = if dir = "INCOMING" then 
                        getRelationTableIncoming(baseUrl, language, sourceClass, relationName, targetClass, repositoryId)
                     else if dir = "OUTGOING" then
                        getRelationTableOutgoing(baseUrl, language, sourceClass, relationName, targetClass, repositoryId)
                     else
                        getRelationTable(baseUrl, language, sourceClass, relationName, targetClass, repositoryId)
        in
            result;

// Function to get available classes
GetAvailableClassesFunction = (baseUrl as text, language as text) =>
    () =>
        let
            metaModelUrl = getBaseURL(baseUrl) & "metamodel/classes/",
            metaModelResponse = getRequest(baseUrl, language, metaModelUrl),
            classes = List.Select(metaModelResponse[classes], each IsVisibleConcreteClass(_)),
            
            // Resolve the same localized display name used by the Navigator.
            // Current metamodel responses expose it through displayNames rather
            // than the legacy top-level name field.
            classRows = List.Transform(
                classes,
                (classRecord as record) =>
                    let
                        metaName = Text.From(GetClassMetaName(classRecord))
                    in
                        [
                            MetaName = metaName,
                            ClassName = GetHumanReadableClassName(classRecord, metaName, language)
                        ]
            ),
            concreteClasses = Table.FromRecords(
                classRows,
                type table [MetaName = text, ClassName = text]
            ),
            
            // Add example usage column
            classesWithExamples = Table.AddColumn(concreteClasses, "Example Usage", 
                each GetLoadClassExample([MetaName], "NAME"), type text),
                
            // Reorder and select columns for display
            resultTable = Table.SelectColumns(classesWithExamples, {"MetaName", "ClassName", "Example Usage"})
        in
            resultTable;

// Function to get available attributes for a class
GetClassAttributesFunction = (baseUrl as text, language as text) =>
    (className as text) =>
        let
            classRecord = try ResolveClassByMetaName(baseUrl, language, className) otherwise null,
            
            // If class wasn't found by name, return an error message
            classResult = if classRecord = null then
                             #table({"Message"}, {{"Class '" & className & "' not found. Check the class name and try again."}})
                          else
                             let
                                 classId = classRecord[id],
                                 
                                 // Get attributes for this class
                                 attrUrl = getBaseURL(baseUrl) & "metamodel/classes/" & classId & "/notebook/",
                                 attrResponse = getRequest(baseUrl, language, attrUrl),
                                 chapters = List.Transform(attrResponse[chapters], each _[children]),
                                 
                                 // Transform to table
                                 attrsTable = Table.FromList(chapters, Splitter.SplitByNothing(), null, null, ExtraValues.Error),
                                 expandedAttrs = Table.ExpandListColumn(attrsTable, "Column1"),
                                 expandedDetails = Table.ExpandRecordColumn(expandedAttrs, "Column1", 
                                     {"id", "metaName", "displayNames", "properties"}, 
                                     {"AttrID", "MetaName", "DisplayNames", "Properties"}),
                                     
                                 // Pick the readable name for the selected language
                                 expandedNames = Table.RemoveColumns(
                                     Table.AddColumn(
                                         expandedDetails,
                                         "Name",
                                         each PickDisplayName([DisplayNames], language),
                                         type nullable text
                                     ),
                                     {"DisplayNames"}
                                 ),
                                 
                                 // Add example usage
                                 withExamples = Table.AddColumn(expandedNames, "Example Usage", 
                                     each "Use in attributes list: {""" & [MetaName] & """}", type text),
                                 
                                 // Select and reorder columns
                                 resultTable = Table.SelectColumns(withExamples, {"MetaName", "Name", "Example Usage"})
                             in
                                 resultTable
        in
            classResult;

// Function to get an object with specific attributes
GetObjectWithAttributesFunction = (baseUrl as text, language as text) =>
    (objectName as text, attributes as list, optional repositoryId as text) =>
        let
            result = getObjectWithType(baseUrl, language, objectName, attributes, {}, repositoryId)
        in
            result;

// Function to get all available relations for a class
GetClassRelationsFunction = (baseUrl as text, language as text) =>
    (className as text) =>
        let
            classRecord = try ResolveClassByMetaName(baseUrl, language, className) otherwise null,
            
            // If class wasn't found by name, return an error message
            classResult = if classRecord = null then
                             #table({"Message"}, {{"Class '" & className & "' not found. Check the class name and try again."}})
                          else
                             let
                                 classId = classRecord[id],
                                 
                                 // Get relations for this class
                                 relUrl = getBaseURL(baseUrl) & "metamodel/classes/" & classId & "/relations/",
                                 relResponse = getRequest(baseUrl, language, relUrl),
                                 relations = relResponse[relations],
                                 
                                 // Transform to table
                                 relTable = Table.FromList(relations, Splitter.SplitByNothing(), null, null, ExtraValues.Error),
                                 expandedRels = Table.ExpandRecordColumn(relTable, "Column1", 
                                     {"id", "metaName", "name", "toClass", "toClassName", "fromClassName", "displayNames"}, 
                                     {"RelationID", "MetaName", "TechnicalName", "ToClassID", "ToClassName", "FromClassName", "DisplayNames"}),
                                 
                                 // Pick the readable name for the selected language
                                 expandedNames = Table.RemoveColumns(
                                     Table.AddColumn(
                                         expandedRels,
                                         "Name",
                                         each PickDisplayName([DisplayNames], language),
                                         type nullable text
                                     ),
                                     {"DisplayNames"}
                                 ),
                                 
                                 // Add directions info and examples
                                 withDirections = Table.AddColumn(expandedNames, "Directions", each 
                                     if [FromClassName] = className and [ToClassName] <> null then 
                                         "OUTGOING to " & [ToClassName]
                                     else if [ToClassName] = className and [FromClassName] <> null then
                                         "INCOMING from " & [FromClassName]
                                     else 
                                         "BOTH", type text),
                                         
                                 withExamples = Table.AddColumn(withDirections, "Example Usage", 
                                     each "GetCustomRelationFunction(""" & className & """, """ & [MetaName] & """, """ & 
                                          (if [FromClassName] = className then [ToClassName] else [FromClassName]) & """)", type text),
                                 
                                 // Select and reorder columns
                                 resultTable = Table.SelectColumns(withExamples, {"MetaName", "Name", "Directions", "Example Usage"})
                             in
                                 resultTable
        in
            classResult;

// Helper functions for the connector

// getRequest using authentication from the connector
getRequest = (baseUrl as text, language as text, request_url as text) =>
    let
        relativePath = Text.Replace(request_url, baseUrl, ""),
        result = Json.Document(Web.Contents(baseUrl, [
            RelativePath = relativePath,
            Headers = [
                Accept = "application/json",
                #"Accept-Language" = language
            ]
            //ManualStatusHandling = {400, 401, 403, 404, 500}
        ]))
    in
        result;

getBaseURL = (baseUrl as text) =>
    let
        result = if Text.EndsWith(baseUrl, "/") then baseUrl & "rest/4.0/" else baseUrl & "/rest/4.0/"
    in
        result;

getRepoID = (baseUrl as text, language as text, repoIndex as number) =>
    let
        response = getRequest(baseUrl, language, getBaseURL(baseUrl) & "repos/"),
        repos = response[repos],
        repo = if repoIndex < 1 or repoIndex > List.Count(repos) then
                   error Error.Record("Repository Error", "Repository index is out of range.", [RepositoryIndex = repoIndex, RepositoryCount = List.Count(repos)])
               else
                   repos{repoIndex - 1},
        result = Text.Replace(Text.Replace(Text.From(repo[id]), "{" , ""), "}" , "")
    in
        result;

searchObject = (baseUrl as text, language as text, objectName as text, optional repositoryId as text) =>
    let
        repoID = if repositoryId = null then getRepoID(baseUrl, language, 1) else repositoryId,
        result = getRequest(baseUrl, language, getBaseURL(baseUrl) & "repos/" & repoID & "/search?range-start=0&query=%7Bfilters%3A%5B%7B%22className%22%3A%22" & objectName & "%22%7D%5D%7D&range-end=-1&")
    in
        result;

searchObjectAttributes = (baseUrl as text, language as text, objectName as text, attributes as list, relationDirection as text, optional repositoryId as text) =>
    let
        repoID = if repositoryId = null then getRepoID(baseUrl, language, 1) else repositoryId,
        result = searchObjectWithJob(baseUrl, language, objectName, attributes, relationDirection, repoID)
    in
        result;

expandAllColumns = let func = (TABLE as table, NAME as list, index as number) =>
    if index >= List.Count(NAME)
                    then TABLE
                    else @func(Table.ExpandListColumn(Table.Distinct(TABLE), NAME{index}), NAME, index + 1) 
in
    func;

extractAllColumns = let func = (TABLE as table, NAME as list, index as number, delimiter as text) =>
    if index >= List.Count(NAME)
                    then TABLE
                    else @func(Table.TransformColumns(Table.Distinct(TABLE), {NAME{index}, each Text.Combine(List.Transform(_, Text.From), delimiter), type text}), NAME, index + 1, delimiter) 
in
    func;

// Shared post-processing for search hits. The object search and the saved
// search both feed their raw items through this function so every table is
// built the same way. The getter type only decides whether the Type column is
// kept, whether relation targets are reported by name or by ID, and whether
// multiple values are combined into one delimited cell.
ProcessSearchItems = (items as list, langIndependentAttributes as list, langDependentAttributes as list, getterType as text, optional delimiter as text) =>
    let
        includeType = getterType = "WITH_TYPE" or getterType = "WITH_TYPE_NAME_DELIMITER",
        useTargetNames = getterType = "WITH_NAME" or getterType = "WITH_NAME_DELIMITER" or getterType = "WITH_TYPE_NAME_DELIMITER",
        combineWithDelimiter = getterType = "WITH_NAME_DELIMITER" or getterType = "WITH_TYPE_NAME_DELIMITER",
        EmptyResult = if includeType then #table({"ID", "Type"}, {}) else #table({"ID"}, {}),
        // Supplying Column1 explicitly keeps the transformation valid when the
        // search returns an empty list.
        #"In Tabelle konvertiert" = Table.FromList(items, Splitter.SplitByNothing(), {"Column1"}, null, ExtraValues.Error),
        #"Erweiterte Column1" = Table.ExpandRecordColumn(#"In Tabelle konvertiert", "Column1", {"rest_links", "id", "name", "type", "artefactType", "metaName", "link", "icon", "attributes"}, {"Column1.rest_links", "Column1.id", "Column1.name", "Column1.type", "Column1.artefactType", "Column1.metaName", "Column1.link", "Column1.icon", "Column1.attributes"}),
        DefaultRemoveColumns = Table.RemoveColumns(#"Erweiterte Column1",{"Column1.type", "Column1.artefactType", "Column1.metaName", "Column1.link", "Column1.icon"}),
        WithTypeRemoveColumns = Table.RemoveColumns(#"Erweiterte Column1",{"Column1.artefactType", "Column1.metaName", "Column1.link", "Column1.icon"}),
        #"Entfernte Spalten" = if includeType then WithTypeRemoveColumns else DefaultRemoveColumns,
        #"Erweiterte Column1.attributes" = Table.ExpandListColumn(#"Entfernte Spalten", "Column1.attributes"),
        #"Entfernte Spalten1" = Table.RemoveColumns(#"Erweiterte Column1.attributes",{"Column1.rest_links"}),
        FilteredRows = Table.SelectRows(#"Entfernte Spalten1", each 
            let
                attributes = [Column1.attributes],
                metaNameExists = Record.Field(attributes, "metaName") = "NAME",
                nameInlangIndependentAttributes = List.Contains(langIndependentAttributes, "NAME")
            in
                not (metaNameExists and not nameInlangIndependentAttributes)
        ),
        #"Erweiterte Column1.attributes1" = Table.ExpandRecordColumn(FilteredRows, "Column1.attributes", {"name", "attrType", "value", "targets"}, {"Column1.attributes.name", "Column1.attributes.attrType", "Column1.attributes.value", "Column1.attributes.targets"}),
        #"Erweiterte Column1.attributes.targets" = Table.ExpandListColumn(#"Erweiterte Column1.attributes1", "Column1.attributes.targets"),
        DefaultExpandColumns = Table.ExpandRecordColumn(#"Erweiterte Column1.attributes.targets", "Column1.attributes.targets", {"id"}, {"Column1.attributes.targets.name"}),
        WithNameOrWithNameDelimiterExpandColumns = Table.ExpandRecordColumn(#"Erweiterte Column1.attributes.targets", "Column1.attributes.targets", {"name"}, {"Column1.attributes.targets.name"}),
        #"Erweiterte Column1.attributes.targets1" = if useTargetNames then WithNameOrWithNameDelimiterExpandColumns else DefaultExpandColumns,
        #"Zusammengeführte Spalte eingefügt" = Table.AddColumn(#"Erweiterte Column1.attributes.targets1", "Attributwert", each Text.Combine({[Column1.attributes.targets.name], Text.From([Column1.attributes.value], "de-AT")}, ""), type text),
        #"Entfernte Spalten2" = Table.RemoveColumns(#"Zusammengeführte Spalte eingefügt",{"Column1.attributes.value", "Column1.attributes.targets.name"}),
        #"Removed Errors" = Table.RemoveRowsWithErrors(#"Entfernte Spalten2", {"Attributwert"}),
        #"Umbenannte Spalten" = Table.RenameColumns(#"Removed Errors",{{"Column1.attributes.name", "Attribut"}, {"Column1.attributes.attrType", "Attributtyp"}, {"Column1.name", "Prozess"}}),
        // The grouping keys also determine the column order of the result, so
        // keep ID first and put Type directly behind it.
        #"Gruppierte Zeilen" = if includeType then Table.Group(#"Umbenannte Spalten", {"Column1.id", "Column1.type", "Prozess", "Attribut"},{{"Anzahl", each Text.Combine([Attributwert], " ;] "), type text}}) else Table.Group(#"Umbenannte Spalten", {"Column1.id", "Prozess", "Attribut"}, {{"Anzahl", each Text.Combine([Attributwert], " ;] "), type text}}),
        #"Pivotierte Spalte" = Table.Pivot(#"Gruppierte Zeilen", List.Distinct(#"Gruppierte Zeilen"[Attribut]), "Attribut", "Anzahl", each Text.Split(Text.Combine(_), " ;] ")),
        #"Removed Columns" = if Table.HasColumns(#"Pivotierte Spalte", {"ID"}) then Table.RemoveColumns(#"Pivotierte Spalte",{"Prozess", "ID"}) else Table.RemoveColumns(#"Pivotierte Spalte",{"Prozess"}),
        DefaultRenameColumns = Table.RenameColumns(#"Removed Columns",{{"Column1.id", "ID"}}),
        WithTypeRenameColumns = Table.RenameColumns(#"Removed Columns",{{"Column1.id", "ID"},{"Column1.type", "Type"}}),
        #"Renamed Columns" = if includeType then WithTypeRenameColumns else DefaultRenameColumns,
        Selector = if List.Count(langDependentAttributes) = 0 then #"Renamed Columns" else Table.SelectColumns(#"Renamed Columns", List.Combine({{"ID"}, langDependentAttributes})),
        CustomDelimiter = if delimiter = null then ";" else delimiter,
        // The identity columns come first, so skip them and only combine or
        // expand the attribute columns behind them.
        FirstAttributeIndex = if includeType then 2 else 1,
        #"Expanding Columns" = if combineWithDelimiter then extractAllColumns(Selector, Table.ColumnNames(Selector), FirstAttributeIndex, CustomDelimiter) else expandAllColumns(Selector, Table.ColumnNames(Selector), FirstAttributeIndex),
        #"Removed Duplicates" = Table.Distinct(#"Expanding Columns"),
        // Lead with the identity columns and the object name. Everything the
        // reorder list does not mention keeps the order the search returned it
        // in, and columns that are absent are simply skipped.
        #"Ordered Columns" = Table.ReorderColumns(
            #"Removed Duplicates",
            List.Distinct({"ID", "Type", "Name"} & Table.ColumnNames(#"Removed Duplicates")),
            MissingField.Ignore
        ),
        Result = if List.IsEmpty(items) then EmptyResult else #"Ordered Columns"
    in
        Result;

_getObject = (baseUrl as text, language as text, objectName as text, langIndependentAttributes as list, langDependentAttributes as list, getterType as text, optional delimiter as text, optional relationDirection as text, optional repositoryId as text) =>
    let
        relationDirectionWithDefault = if relationDirection = null then "BOTH" else relationDirection,
        Quelle = if List.Count(langIndependentAttributes) = 0 then searchObject(baseUrl, language, objectName, repositoryId) else searchObjectAttributes(baseUrl, language, objectName, langIndependentAttributes, relationDirectionWithDefault, repositoryId),
        rawItemsValue = Record.FieldOrDefault(Quelle, "items", {}),
        rawItems = if Value.Is(rawItemsValue, type list) then rawItemsValue else {},
        items = List.Transform(
            List.Select(rawItems, each Value.Is(_, type record)),
            each NormalizeSearchItem(_)
        ),
        Result = ProcessSearchItems(items, langIndependentAttributes, langDependentAttributes, getterType, delimiter)
    in
        Result;

// Exported function implementations
getObject = (baseUrl as text, language as text, objectName as text, langIndependantAttributes as list, langDependantAttributes as list, optional repositoryId as text) =>
    _getObject(baseUrl, language, objectName, langIndependantAttributes, langDependantAttributes, "DEFAULT", null, null, repositoryId);

getObjectWithName = (baseUrl as text, language as text, objectName as text, langIndependentAttributes as list, langDependentAttributes as list, optional repositoryId as text) =>
    _getObject(baseUrl, language, objectName, langIndependentAttributes, langDependentAttributes, "WITH_NAME", null, null, repositoryId);

getObjectWithNameDelimiter = (baseUrl as text, language as text, objectName as text, langIndependentAttributes as list, langDependentAttributes as list, delimiter, optional repositoryId as text) =>
    _getObject(baseUrl, language, objectName, langIndependentAttributes, langDependentAttributes, "WITH_NAME_DELIMITER", delimiter, null, repositoryId);

getObjectWithType = (baseUrl as text, language as text, objectName as text, langIndependentAttributes as list, langDependentAttributes as list, optional repositoryId as text) =>
    _getObject(baseUrl, language, objectName, langIndependentAttributes, langDependentAttributes, "WITH_TYPE", null, null, repositoryId);

getObjectWithTypeAndRelationDirection = (baseUrl as text, language as text, objectName as text, langIndependentAttributes as list, langDependentAttributes as list, relationDirection as text, optional repositoryId as text) =>
    _getObject(baseUrl, language, objectName, langIndependentAttributes, langDependentAttributes, "WITH_TYPE", null, relationDirection, repositoryId);

_getRelationTable = (baseUrl as text, language as text, objectA as text, relationName as text, objectB as text, relationDirection as text, optional repositoryId as text) =>
    let
        ClassA = if relationDirection = "INCOMING" then
                     getObjectWithTypeAndRelationDirection(baseUrl, language, objectA, {relationName}, {}, "INCOMING", repositoryId)
                 else if relationDirection = "OUTGOING" then
                     getObjectWithTypeAndRelationDirection(baseUrl, language, objectA, {relationName}, {}, "OUTGOING", repositoryId)
                 else
                     getObjectWithType(baseUrl, language, objectA, {relationName}, {}, repositoryId),
        ClassB = getObjectWithType(baseUrl, language, objectB, {"NAME"}, {}, repositoryId),
        ClassAName = if not Table.IsEmpty(ClassA) and Table.HasColumns(ClassA, "Type") then Text.From(Table.First(ClassA)[Type]) else objectA,
        ClassBName = if not Table.IsEmpty(ClassB) and Table.HasColumns(ClassB, "Type") then Text.From(Table.First(ClassB)[Type]) else objectB,
        RelationColumns = List.RemoveItems(Table.ColumnNames(ClassA), {"Type", "ID"}),
        RelationColumnName = List.First(RelationColumns, null),
        OutputColumnNames = if relationDirection = "INCOMING" then
                                {"To: " & ClassAName, "From: " & ClassBName}
                            else if relationDirection = "OUTGOING" then
                                {"From: " & ClassAName, "To: " & ClassBName}
                            else
                                {"1" & ClassAName, ClassBName},
        EmptyResult = #table(OutputColumnNames, {}),
        Result = if Table.IsEmpty(ClassA) or Table.IsEmpty(ClassB) or RelationColumnName = null then
                     EmptyResult
                 else
                     let
                         RenamedRelation = Table.RenameColumns(ClassA, {{RelationColumnName, "RELATION"}}),
                         FilterList = List.Buffer(Table.Column(ClassB, "ID")),
                         FilteredRows = Table.SelectRows(RenamedRelation, each List.Contains(FilterList, [RELATION])),
                         RemovedType = Table.RemoveColumns(FilteredRows, {"Type"}),
                         RenamedResult = Table.RenameColumns(RemovedType, {{"ID", OutputColumnNames{0}}, {"RELATION", OutputColumnNames{1}}})
                     in
                         RenamedResult
    in
        Result;

getRelationTable = (baseUrl as text, language as text, objectA as text, relationName as text, objectB as text, optional repositoryId as text) =>
    _getRelationTable(baseUrl, language, objectA, relationName, objectB, "BOTH", repositoryId);

getRelationTableIncoming = (baseUrl as text, language as text, objectA as text, relationName as text, objectB as text, optional repositoryId as text) =>
    _getRelationTable(baseUrl, language, objectA, relationName, objectB, "INCOMING", repositoryId);

getRelationTableOutgoing = (baseUrl as text, language as text, objectA as text, relationName as text, objectB as text, optional repositoryId as text) =>
    _getRelationTable(baseUrl, language, objectA, relationName, objectB, "OUTGOING", repositoryId);

// Data Source Kind description
BOCADONISADOITConnector = [
    Authentication = [
        OAuth = [
            StartLogin = StartLogin,
            FinishLogin = FinishLogin,
            Refresh = Refresh
        ]
    ],
    Label = Extension.LoadString("DataSourceLabel")
];

windowWidth = 1200;
windowHeight = 1000;
default_client_id = "PowerBIID";
redirect_uri = "https://oauth.powerbi.com/views/oauthredirect.html";

Base64Url.Encode = (value as binary) as text =>
    Text.Replace(
        Text.Replace(
            Text.BeforeDelimiter(Binary.ToText(value, BinaryEncoding.Base64), "="),
            "+",
            "-"
        ),
        "/",
        "_"
    );

// OAuth errors from ADOIT/ADONIS are returned in response headers and can have
// an empty response body. Reading that body directly with Json.Document raises
// the misleading "We reached the end of the Buffer" error, so inspect both the
// response metadata and the optional JSON payload.
OAuth.GetFieldIgnoreCase = (recordValue as any, fieldName as text) as any =>
    let
        fieldNames = if Value.Is(recordValue, type record) then Record.FieldNames(recordValue) else {},
        matchingField = List.First(
            List.Select(fieldNames, each Text.Lower(_) = Text.Lower(fieldName)),
            null
        )
    in
        if matchingField = null then null else Record.Field(recordValue, matchingField);

// Read a field from a stored OAuth credential. The advanced Refresh callback
// normally receives the flat record returned by FinishLogin, but a credential
// coming back through Extension.CurrentCredential carries the connector's own
// fields nested under Properties, so look in both places.
OAuth.GetCredentialField = (credential as any, fieldName as text) as any =>
    let
        direct = OAuth.GetFieldIgnoreCase(credential, fieldName),
        properties = OAuth.GetFieldIgnoreCase(credential, "Properties"),
        nested = if direct = null then OAuth.GetFieldIgnoreCase(properties, fieldName) else null
    in
        if direct <> null then direct else nested;

// Secrets must never be written into an error message or a trace in full. A
// length and a short prefix are enough to tell whether the right value was sent
// and whether it changed between two calls.
OAuth.Redact = (value as any) as text =>
    if value = null then
        "<missing>"
    else
        let
            asText = Text.From(value)
        in
            if Text.Trim(asText) = ""
            then "<empty>"
            else "len=" & Text.From(Text.Length(asText)) & " prefix=" & Text.Start(asText, 6);

OAuth.ParseTokenResponse = (tokenResponse as binary, errorReason as text, optional requestDiagnostics as nullable record) as record =>
    let
        // The response body is a forward-only stream. This function inspects it
        // twice - once for the metadata, once for the JSON - so it has to be
        // buffered first, otherwise the second read sees nothing and reports a
        // valid token response as empty.
        bufferedResponse = Binary.Buffer(tokenResponse),
        bufferedLength = try Binary.Length(bufferedResponse) otherwise 0,
        // Reading the metadata is written to depend on the buffered value so it
        // cannot be evaluated before the body has been materialised. M orders
        // let bindings by dependency, not by the order they are written in.
        responseMetadata = if bufferedLength >= 0 then Value.Metadata(tokenResponse) else [],
        responseStatusValue = Record.FieldOrDefault(responseMetadata, "Response.Status", 200),
        responseStatus = try Number.From(responseStatusValue) otherwise 200,
        responseHeadersValue = Record.FieldOrDefault(responseMetadata, "Headers", []),
        responseHeaders = if Value.Is(responseHeadersValue, type record) then responseHeadersValue else [],
        // An empty body is a real case here: these servers report OAuth errors
        // in the response headers and send no payload at all.
        parsedResponse =
            if bufferedLength = 0
            then [HasError = true, Value = null]
            else try Json.Document(bufferedResponse),
        responseObject =
            if parsedResponse[HasError] then
                []
            else if Value.Is(parsedResponse[Value], type record) then
                parsedResponse[Value]
            else
                [],
        errorCode = List.First(
            List.RemoveNulls({
                OAuth.GetFieldIgnoreCase(responseObject, "error"),
                OAuth.GetFieldIgnoreCase(responseHeaders, "error")
            }),
            null
        ),
        errorDescriptionValue = List.First(
            List.RemoveNulls({
                OAuth.GetFieldIgnoreCase(responseObject, "error_description"),
                OAuth.GetFieldIgnoreCase(responseHeaders, "error_description")
            }),
            null
        ),
        errorDescription =
            if errorDescriptionValue <> null then
                Text.From(errorDescriptionValue)
            else if errorCode <> null then
                Text.From(errorCode)
            else if responseStatus >= 400 then
                "The token endpoint rejected the request (HTTP " & Text.From(responseStatus) & ")."
            else if bufferedLength = 0 then
                "The token endpoint returned HTTP " & Text.From(responseStatus) & " with an empty body."
            else
                // Include the start of the payload: if this ever fires again the
                // message should say what actually came back instead of guessing.
                "The token endpoint returned HTTP " & Text.From(responseStatus) &
                " with a body that is not valid JSON: " &
                (try Text.Start(Text.FromBinary(bufferedResponse), 200) otherwise "<unreadable>"),
        // Everything known about the exchange travels with the error. The token
        // endpoint often sends only an error code, so the response headers and
        // body are usually the only way to tell why a grant was refused.
        diagnostics =
            (if requestDiagnostics = null then [] else requestDiagnostics) & [
                Status = responseStatus,
                ResponseHeaders = responseHeaders,
                ResponseBody =
                    if bufferedLength = 0
                    then "<empty>"
                    else (try Text.Start(Text.FromBinary(bufferedResponse), 2000) otherwise "<unreadable>")
            ],
        result =
            if responseStatus >= 400 or errorCode <> null then
                error Error.Record(errorReason, errorDescription, diagnostics & [OAuthError = errorCode])
            else if parsedResponse[HasError] then
                error Error.Record(errorReason, errorDescription, diagnostics)
            else if not Record.HasFields(responseObject, "access_token") then
                error Error.Record(errorReason, "The token endpoint did not return an access token.", diagnostics)
            else
                responseObject
    in
        result;

StartLogin = (resourceUrl, state, display) =>
    let
        dataSourcePath = Json.Document(resourceUrl),
        baseUrl = dataSourcePath[baseUrl],
        configuredClientId = Record.FieldOrDefault(dataSourcePath, "client_id", null),
        effectiveClientId = if configuredClientId = null or Text.Trim(configuredClientId) = "" then default_client_id else configuredClientId,
        baseUrlWithSlash = if Text.EndsWith(baseUrl, "/") then baseUrl else baseUrl & "/",
        CodeVerifier = Text.NewGuid() & Text.NewGuid() & Text.NewGuid(),
        CodeChallenge = Base64Url.Encode(Crypto.CreateHash(CryptoAlgorithm.SHA256, Text.ToBinary(CodeVerifier))),
        
        // Build the authorization URL for the ADONIS/ADOIT OAuth endpoint
        AuthorizeUrl = baseUrlWithSlash & "oauth2/authorize?" & Uri.BuildQueryString([
            client_id = effectiveClientId,
            response_type = "code",
            state = state,
            code_challenge = CodeChallenge,
            code_challenge_method = "S256"
        ])
    in
        [
            LoginUri = AuthorizeUrl,
            CallbackUri = redirect_uri,
            WindowHeight = windowHeight,
            WindowWidth = windowWidth,
            Context = [
                base_url = baseUrlWithSlash,
                code_verifier = CodeVerifier,
                state = state,
                client_id = effectiveClientId
            ]  
        ];

FinishLogin = (context, callbackUri, state) => 
    let
        Parts = Uri.Parts(callbackUri)[Query],
        accessCode = Record.FieldOrDefault(Parts, "code", null),
        callbackState = Record.FieldOrDefault(Parts, "state", null),

        // Get the token using the authorization code
        queryParams = Uri.BuildQueryString([
            grant_type = "authorization_code",
            code = accessCode,
            code_verifier = context[code_verifier],
            client_id = context[client_id]
        ]),
        tokenUrl = context[base_url] & "oauth2/token?" & queryParams,

        tokenResponse = if callbackState = null or callbackState <> context[state] then
                            error Error.Record("OAuth Error", "State mismatch - possible CSRF attack", [
                                ExpectedState = context[state],
                                ReceivedState = callbackState
                            ])
                        else if accessCode = null then
                            error Error.Record("OAuth Error", "The authorization response did not contain an authorization code.", Parts)
                        else
                            Web.Contents(tokenUrl, [
                                Content=Text.ToBinary(""),
                                Headers = [
                                    #"Content-Type" = "application/x-www-form-urlencoded",
                                    #"Accept" = "application/json"
                                ],
                                ManualStatusHandling = {400, 401, 403}
                            ]),

        // Share the token-response parser with Refresh so a failed sign-in
        // reports the server's OAuth error instead of a buffer-length error.
        parsedResponse = OAuth.ParseTokenResponse(tokenResponse, "OAuth Error"),

        // The returned record is the credential Power Query stores and hands to
        // the advanced Refresh callback as oldCredential. PKCE applies to the
        // refresh grant too, so the verifier is kept alongside the tokens - the
        // server has no other way to receive it once this login window closes.
        result =
            if Record.HasFields(parsedResponse, "code_verifier") then
                parsedResponse
            else
                Record.AddField(parsedResponse, "code_verifier", context[code_verifier])
    in
        result;

// The advanced Power Query callback provides the complete credential returned
// by FinishLogin (or the previous refresh).
//
// The refresh grant sends grant_type and refresh_token, plus - because ADOXX
// keeps PKCE in force for this grant - the client_id and code_verifier that a
// public client used for the authorization-code exchange.
Refresh = (clientApplication, resourceUrl, oldCredential) =>
    let
        dataSourcePath = Json.Document(resourceUrl),
        baseUrl = dataSourcePath[baseUrl],
        configuredClientId = Record.FieldOrDefault(dataSourcePath, "client_id", null),
        effectiveClientId = if configuredClientId = null or Text.Trim(configuredClientId) = "" then default_client_id else configuredClientId,
        baseUrlWithSlash = if Text.EndsWith(baseUrl, "/") then baseUrl else baseUrl & "/",
        refreshTokenValue = OAuth.GetCredentialField(oldCredential, "refresh_token"),
        refreshToken =
            if refreshTokenValue = null or Text.Trim(Text.From(refreshTokenValue)) = "" then
                error Error.Record(
                    "OAuth Refresh Error",
                    "No refresh token is stored. Clear the data-source permissions and sign in again.",
                    null
                )
            else
                Text.From(refreshTokenValue),
        // PKCE stays in force for the refresh grant: the ADOXX documentation
        // says of the refresh request that "all the rest (client registration,
        // PKCE, error handling etc.) are the same", and a public client's code
        // exchange carries both client_id and code_verifier. Omitting the
        // verifier here makes the token endpoint answer invalid_grant.
        codeVerifierValue = OAuth.GetCredentialField(oldCredential, "code_verifier"),
        codeVerifier =
            if codeVerifierValue = null or Text.Trim(Text.From(codeVerifierValue)) = "" then
                null
            else
                Text.From(codeVerifierValue),
        baseParams = [
            grant_type = "refresh_token",
            refresh_token = refreshToken,
            client_id = effectiveClientId
        ],
        // Missing verifier is not failed here: the request is still worth
        // attempting, and the server's own error is more informative than a
        // guess made locally.
        sentParams =
            if codeVerifier = null
            then baseParams
            else Record.AddField(baseParams, "code_verifier", codeVerifier),
        queryParams = Uri.BuildQueryString(sentParams),
        tokenUrl = baseUrlWithSlash & "oauth2/token?" & queryParams,
        tokenResponse = Web.Contents(tokenUrl, [
            Content = Text.ToBinary(""),
            Headers = [
                #"Content-Type" = "application/x-www-form-urlencoded",
                #"Accept" = "application/json"
            ],
            ManualStatusHandling = {400, 401, 403}
        ]),
        requestDiagnostics = [
            TokenEndpoint = baseUrlWithSlash & "oauth2/token",
            SentParameters = Text.Combine(Record.FieldNames(sentParams), ", "),
            ClientId = effectiveClientId,
            SentRefreshToken = OAuth.Redact(refreshToken),
            SentCodeVerifier = OAuth.Redact(codeVerifier)
        ],
        responseObj = OAuth.ParseTokenResponse(tokenResponse, "OAuth Refresh Error", requestDiagnostics),

        // Note for future debugging: Diagnostics.Trace calls placed here do not
        // reach the Power BI Desktop mashup logs. Refresh runs in the credential
        // service rather than in a query evaluation container, and its traces do
        // not land in Traces\*.log even at Information level. Diagnose this path
        // through the error record below, or with an HTTP proxy.
        //
        // The token endpoint is not documented as rotating refresh tokens, so a
        // response without one keeps the existing token alive for the next cycle.
        withRefreshToken =
            if Record.HasFields(responseObj, "refresh_token") then
                responseObj
            else
                Record.AddField(responseObj, "refresh_token", refreshToken),
        // This record becomes the credential the next refresh receives, so the
        // verifier has to be carried forward or only the first refresh works.
        result =
            if codeVerifier = null then
                withRefreshToken
            else if Record.HasFields(withRefreshToken, "code_verifier") then
                Record.TransformFields(withRefreshToken, {{"code_verifier", each codeVerifier}})
            else
                Record.AddField(withRefreshToken, "code_verifier", codeVerifier)
    in
        result;

// Data Source UI publishing description
BOCADONISADOITConnector.Publish = [
    Beta = true,
    Category = "Other",
    ButtonText = { Extension.LoadString("ButtonTitle"), Extension.LoadString("ButtonHelp") },
    LearnMoreUrl = "https://powerbi.microsoft.com/",
    SourceImage = BOCADONISADOITConnector.Icons,
    SourceTypeImage = BOCADONISADOITConnector.Icons
];

BOCADONISADOITConnector.Icons = [
    Icon16 = { Extension.Contents("BOCIcon16.png"), Extension.Contents("BOCIcon20.png"), Extension.Contents("BOCIcon24.png"), Extension.Contents("BOCIcon32.png") },
    Icon32 = { Extension.Contents("BOCIcon32.png"), Extension.Contents("BOCIcon40.png"), Extension.Contents("BOCIcon48.png"), Extension.Contents("BOCIcon64.png") }
];

// Search request step size (how many items to retrieve per request)
searchRequestStepSize = 1000;

// Create a search job 
createSearchJob = (baseUrl as text, language as text, objectName as text, attributes as list, relationDirection as text, optional repositoryId as text) =>
    let
        repoID = if repositoryId = null then getRepoID(baseUrl, language, 1) else repositoryId,
        
        // Build filters based on relation direction
        baseFilter = [className = objectName],
        additionalFilters = 
            if relationDirection = "BOTH" then {} 
            else 
                List.Transform(
                    attributes, 
                    (attr) => [
                        relName = attr,
                        incoming = if relationDirection = "INCOMING" then true else false,
                        outgoing = if relationDirection = "OUTGOING" then true else false,
                        op = "OP_NEMPTY"
                    ]
                ),
        
        filtersList = List.Combine({ { baseFilter }, additionalFilters }),
        
        // Build the request body
        attributesJson = Text.Combine(List.Transform(attributes, each """" & _ & """"), ","),
        requestBody = "{""filters"":" & Text.FromBinary(Json.FromValue(filtersList)) & 
                     ",""attributes"":[" & attributesJson & "]" & 
                     ",""relations"":[" & attributesJson & "]" & 
                     ",""scope"":{""repoObjects"":true,""modObjects"":true}}",
        
        // Make the request to create the search job
        response = Web.Contents(baseUrl, [
            Content = Text.ToBinary(requestBody),
            Headers = [
                #"Content-Type" = "application/json",
                #"Accept-Language" = language
            ],
            RelativePath = "rest/4.0/repos/" & repoID & "/search/jobs"
            //ManualStatusHandling = {201, 400, 401, 403, 404, 500}
        ]),
        
        // Extract the Location header to get the search job key
        responseHeaders = Value.Metadata(response)[Headers],
        locationHeader = responseHeaders[#"Location"],
        searchJobKey = Text.Middle(locationHeader, Text.PositionOf(locationHeader, "/", Occurrence.Last) + 1)
    in
        searchJobKey;

// Function to create a delay in seconds
Function.WaitFor = (seconds as number) as logical =>
    let
        delay = Function.InvokeAfter(
            () => true,
            #duration(0, 0, 0, seconds)
        )
    in
        delay;

// Search for objects using a search job
searchObjectWithJob = (baseUrl as text, language as text, objectName as text, attributes as list, relationDirection as text, optional repositoryId as text) =>
    let
        repoID = if repositoryId = null then getRepoID(baseUrl, language, 1) else repositoryId,
        
        // Create the search job
        key = createSearchJob(baseUrl, language, objectName, attributes, relationDirection, repoID),
        
        // Add a 5-second delay
        waitResult = Function.WaitFor(5),
        
        // First request to get the total number of hits
        responseForTotal = if waitResult then
                               Json.Document(Web.Contents(baseUrl, [
                                   Headers = [#"Accept-Language" = language],
                                   RelativePath = "rest/4.0/repos/" & repoID & "/search/jobs/" & key,
                                   Query = [#"range-start" = "0", #"range-end" = "1"]
                               ]))
                           else
                               error "Search job wait failed.",
        
        totalAmount = responseForTotal[hitsTotal],
        
        // Generate ranges for paged requests
        generateRanges = (total, step) => 
            let
                indexList = List.Numbers(0, Number.RoundUp(total / step), step),
                ranges = List.Transform(indexList, each {_, if _ + step < total then _ + step - 1 else total - 1})
            in
                ranges,
                
        ranges = generateRanges(totalAmount, searchRequestStepSize),
        
        // Function to retrieve each page of results
        getResultPage = (range) => 
            let
                start = range{0},
                end = range{1},
                response = Json.Document(Web.Contents(baseUrl, [
                    Headers = [#"Accept-Language" = language],
                    RelativePath = "rest/4.0/repos/" & repoID & "/search/jobs/" & key,
                    Query = [#"range-start" = Text.From(start), #"range-end" = Text.From(end)]
                ])),
                items = response[items]
            in
                items,
                
        // Get all results by combining the results from each page
        results = List.Transform(ranges, each getResultPage(_)),
        allItems = List.Combine(results),
        
        // Create a record that looks like the original searchObject response
        response = [items = allItems]
    in
        response;
