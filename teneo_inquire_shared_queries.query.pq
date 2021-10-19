// Use this file to write queries to test the data connector
let
    url = "https://yourteam.data.teneo.ai/teneo-inquire/rest",
    lds = "longberry_baristas_id",
    result = teneo_inquire_shared_queries.Contents(url, lds)
in
    result

    