defmodule Iris.Persona.ConversationsKnowledgeGraphManual do
  alias Iris.{
    ChatSessions,
    Personas
  }

  require Logger

  def run do
    Logger.info("Running Conversations Knowledge Graph manually")

    personas = Personas.all_public_ids()
    Logger.info("Processing persona: #{inspect(length(personas))}")
    # messages = ChatSessions.retrieve_chat_messages()
    # IO.inspect(messages, label: "Messages")

    Enum.each(personas, fn persona ->
      if persona.public_id == "420c9dd4-2cfa-48c1-b8cc-0a4919ac2409" do
        Logger.info("Processing persona: #{persona.name}")
        Logger.info("Processing persona id: #{persona.public_id}")

        sessions_messages = ChatSessions.retrieve_sessions_messages_by_persona(persona.public_id)

        updated_sessions_messages = parse_messages_to_string(persona.name, sessions_messages)

        IO.inspect(updated_sessions_messages, label: "Groups")

        IO.inspect(sessions_messages, label: "Messages for #{persona.public_id}")
        IO.inspect(length(sessions_messages), label: "Messages Count for #{persona.public_id}")

        groups = SessionSplitter.create_chunks_from_sessions(updated_sessions_messages, 10000, 20000, 20)

        # IO.inspect(groups, label: "Groups")

        knowledge_graph = %{"nodes" => [], "relationships" => []}

        knowledge_graph =
          groups
          |> Enum.with_index()
          |> Enum.reduce(knowledge_graph, fn {group, index}, acc_graph ->
            Logger.info("Processing group #{index + 1} with #{length(group.messages)} messages")

            case extract_knowledge_graph(group.messages, acc_graph) do
              {:ok, new_graph} ->
                merge_graph(acc_graph, new_graph)

              {:error, reason} ->
                Logger.error("Failed to extract knowledge graph: #{reason}")
                acc_graph

            end
          end)

          # file_path = "graphs/#{persona.name}_knowledge_graph.json"

          # knowledge_graph =
          #   case File.read(file_path) do
          #     {:ok, json_content} ->
          #       Jason.decode!(json_content)

          #     {:error, reason} ->
          #       IO.puts("Failed to read the file: #{reason}")
          #       %{"nodes" => [], "relationships" => []}
          #   end

          case fix_graph_duplicates(knowledge_graph) do
            {:ok, replacements} ->
              IO.inspect(replacements, label: "Replacements")
              knowledge_graph = apply_replacements(knowledge_graph, replacements)
              # IO.inspect(knowledge_graph, label: "Updated Knowledge Graph")

              knowledge_graph = ensure_connected_to_root(knowledge_graph, persona.name)
              file_path1 = "graphs/#{persona.name}_knowledge_graph1.json"

              :ok = File.write(file_path1, Jason.encode!(knowledge_graph))
            {:error, reason} ->
              IO.puts("Failed to fix duplicates: #{inspect(reason)}")
          end

          # knowledge_graph = apply_replacements(knowledge_graph, %{
          #   "nodes" => [
          #     %{
          #       "node_id_to_merge_into" => "Atlas of Podillia traditional housing",
          #       "node_id_to_replace" => "Atlas of Traditional Ukrainian Housing"
          #     },
          #     %{
          #       "node_id_to_merge_into" => "Ukrainian folk architecture",
          #       "node_id_to_replace" => "українська народна архітектура"
          #     },
          #     %{
          #       "node_id_to_merge_into" => "Ukrainian traditional clothing",
          #       "node_id_to_replace" => "українська культура"
          #     }
          #   ],
          #   "relationships" => [
          #     %{
          #       "relationship_type_to_merge_into" => "studies",
          #       "relationship_type_to_replace" => "focusesOn"
          #     },
          #     %{
          #       "relationship_type_to_merge_into" => "isInterestedIn",
          #       "relationship_type_to_replace" => "isAssociatedWith"
          #     }
          #   ]
          # })
          # file_path1 = "graphs/#{persona.name}_knowledge_graph1.json"

          # knowledge_graph = ensure_connected_to_root(knowledge_graph, persona.name)

          # :ok = File.write(file_path1, Jason.encode!(knowledge_graph))
      end
    end)
  end

  def extract_knowledge_graph(conversation, existing_knowledge_graph) do

    all_nodes = existing_knowledge_graph["nodes"] |> Enum.map(& &1["id"]) |> Enum.join(", ")

    all_relationships =
      existing_knowledge_graph["relationships"]
      |> Enum.map(& &1["type"])
      |> then(fn rels ->
        if "isAssociatedWith" in rels do
          rels
        else
          ["isAssociatedWith" | rels]
        end
      end)
      |> Enum.join(", ")

    system_prompt = """
    # Knowledge Graph Instructions for LLM
    ## 1. Overview
    You are a top-tier algorithm designed for extracting information in structured formats to build a knowledge graph.
    Extract information from the following chat conversation between an AI and a user to build a knowledge graph.
    Follow these guidelines:

    - **Nodes** represent entities and concepts. They're akin to Wikipedia nodes.
    - **Relationships** represent the relationship between different entities or concepts.
    - The aim is to achieve simplicity and clarity in the knowledge graph, making it accessible for a vast audience.
    - Do not include concepts that only make sense in the context of the current conversation. The extracted facts should make sense to refer to in a different context.

    ## 2. Labeling Nodes and Relationships
    - **Consistency**: Ensure you use basic or elementary types for node and relationship labels.
      - For example, when you identify an entity representing a person, always label the type as **"Person"**. Avoid using more specific terms like "mathematician" or "scientist".
      - The type of a relationship should be expressed in passive or present tense. Try to extract relationships that go beyond just what happened temporarily in a conversation, but rather what can be inferred from the conversation.
      - Each node or relationship can only have exactly one type.
    - **Node IDs**: Never utilize integers as node IDs. Node IDs should be names or human-readable identifiers found in the text.

    ## Existing Nodes:\n
    #{all_nodes}\n

    ## Existing Relationships:\n
    #{all_relationships}\n

    ## 3. Source Node Identification
    - **Default Source Node**: If the source node is unclear in the conversation segment, use the person's name as the source node because it is a central node of the knowledge graph.
    - **Node ID**: John Doe: (assistant): - the node id for this node is John Doe.

    ## 4. Handling Numerical Data and Dates
    - Numerical data, like age or other related information, should be incorporated as attributes or properties of the respective nodes.
    - **No Separate Nodes for Dates/Numbers**: Do not create separate nodes for dates or numerical values. Always attach them as attributes or properties of nodes.
    - **Property Format**: Properties must be in a key-value format.
    - **Quotation Marks**: Never use escaped single or double quotes within property values.
    - **Naming Convention**: Use camelCase for property keys, e.g., `birthDate`.

    ## 5. Co-reference Resolution
    - **Maintain Entity Consistency**: When extracting entities, it's vital to ensure consistency.
    If an entity, such as "John Doe", is mentioned multiple times in the text but is referred to by different names or pronouns (e.g., "Joe", "he"),
    always use the most complete identifier for that entity throughout the knowledge graph. In this example, use "John Doe" as the entity ID.
    Remember, the knowledge graph should be coherent and easily understandable, so maintaining consistency in entity references is crucial.

    ## 6. Reusing Existing Nodes/Relationships
    - **Verify Alignment**: Reuse entities or relationships from the existing graph only if they match nodes or connections in the new conversation.
      - If alignment is unclear, create new nodes or relationships.
    - **Avoid Blind Reuse**: Do not reuse existing entities or relationships if they do not logically fit the new data.

    ## 7. Relationship Context
    - Extract relationships from both explicit mentions and inferred context.
    - Avoid overly specific or temporary relationships.

    ## 8. Constraints
    - Adhere to the rules strictly. Non-compliance will result in termination.
    - Ensure that in relationships all source and target nodes are mentioned in nodes.
    - Ensure that all nodes have a relationship with at least one other node.
    - Do not include useless, redundant information or less informative nodes. Graph must be clear and describe useful knowledge

    """

    instructions = [
      %{
        role: :system,
        content: system_prompt
      },
      %{
        role: :user,
        content: """
        Extract a knowledge graph from the following conversation: Ensure the graph is coherent, focused, and easily navigable. Nodes should represent meaningful concepts or summarized ideas, avoiding vague or redundant information.
        #{conversation}
        """
      }
    ]

    params = %{
      model: "gpt-4o-2024-11-20",
      temperature: 0,
      messages: instructions,
      response_format: %{
        type: "json_schema",
        json_schema: %{
          name: :knowledge_graph,
          schema: %{
            type: "object",
            properties: %{
              nodes: %{
                type: "array",
                items: %{
                  type: "object",
                  properties: %{
                    id: %{type: "string", description: "Words separated by space"},
                    type: %{type: "string"},
                    properties: %{
                      type: "array",
                      items: %{
                        type: "object",
                        properties: %{
                          key: %{type: "string"},
                          value: %{type: "string"}
                        },
                        required: ["key", "value"],
                        additionalProperties: false
                      }
                    }
                  },
                  required: ["id", "type", "properties"],
                  additionalProperties: false
                }
              },
              relationships: %{
                type: "array",
                items: %{
                  type: "object",
                  properties: %{
                    source: %{type: "string"},
                    target: %{type: "string"},
                    type: %{type: "string", description: "Maximum of 3 words. Each word must be distinct and separated, not written as a single combined phrase."},
                    properties: %{
                      type: "array",
                      items: %{
                        type: "object",
                        properties: %{
                          key: %{type: "string"},
                          value: %{type: "string"}
                        },
                        required: ["key", "value"],
                        additionalProperties: false
                      }
                    }
                  },
                  required: ["source", "target", "type", "properties"],
                  additionalProperties: false
                }
              }
            },
            required: ["nodes", "relationships"],
            additionalProperties: false
          },
          strict: true
        }
      }
    }

    generate_knowledge_graph(params)
  end

  defp generate_knowledge_graph(params, retries \\ 3) do
    IO.puts("Calling LLM...#{4 - retries} attempt")

    try do
      case Iris.AI.ChatCompletion.complete_chat(params) do
        {:ok, raw_data} ->
          IO.inspect(raw_data, label: "Raw LLM Response")
          case Jason.decode(raw_data) do
            {:ok, %{"nodes" => nodes, "relationships" => relationships} = result} ->
              timestamp = DateTime.utc_now() |> DateTime.to_unix()
              file_path = "graphs/#{timestamp}.json"

              IO.puts(raw_data)

              case File.write(file_path, Jason.encode!(result)) do
                :ok ->
                  IO.puts("File written successfully")

                {:error, reason} ->
                  IO.puts("Failed to write file: #{inspect(reason)}")
                  {:error, :file_write_failed}
              end

              {:ok, %{nodes: nodes, relationships: relationships}}

            {:ok, unexpected} ->
              IO.inspect(unexpected, label: "Unexpected Decoded Response")
              {:error, :unexpected_format}

            {:error, decode_error} ->
              IO.inspect(raw_data, label: "Raw LLM Response")
              IO.inspect(decode_error, label: "JSON Decode Error")
              {:error, :invalid_json}
          end

        {:error, reason} ->
          IO.inspect(reason, label: "LLM Request Failed")

          if retries > 0 do
            IO.puts("Retrying... (#{retries} attempts left)")
            generate_knowledge_graph(params, retries - 1)
          else
            IO.puts("No retries left, returning failure")
            {:error, :request_failed}
          end
      end
    rescue
      e in Exception ->
        IO.puts("Error during graph generation: #{inspect(e)}")
        {:error, :exception_occurred}
    end
  end


  def fix_graph_duplicates(existing_knowledge_graph) do

    # all_nodes = existing_knowledge_graph["nodes"] |> Enum.map(& &1["id"]) |> Enum.join(", ")
    # all_relationships = existing_knowledge_graph["relationships"] |> Enum.map(& &1["type"]) |> Enum.join(", ")

    system_prompt = """
    # Knowledge Graph Cleanup Instructions
    Your task is to clean up the knowledge graph by identifying and fixing duplicates in nodes and relationships.
    Follow these guidelines:

    ## Nodes:
    - Identify semantically similar or identical nodes that can be merged into one. For example, "Company" and "Organization".
    - Provide a list of replacements where each object has:
      - "node_id_to_replace": the ID of the node to be replaced.
      - "node_id_to_merge_into": the ID of the node it should be merged into.
    - Do not merge nodes with vague or unrelated meanings.
    - The list can be empty if no duplicate nodes exist.

    - "Atlas of Podillia traditional housing" and "Atlas of Traditional Ukrainian Housing" (these   represent the same concept).
    - "Ukrainian folk architecture" and "українська народна архітектура" (these represent the same concept in different languages).
    - Avoid merging "Ukrainian traditional clothing" with "українська культура" unless there is explicit evidence that they are the same concept.

    ## Relationships:
    - Identify duplicate or semantically similar relationship types. For example, "CO-FOUNDER" and "COFOUNDEROF" can be merged into one consistent type.
    - Provide a list of replacements where each object has:
      - "relationship_type_to_replace": the type of the relationship to be replaced.
      - "relationship_type_to_merge_into": the type of the relationship it should be merged into.
    - The list can be empty if no duplicate relationships exist.

    - "isLocatedIn" and "isFoundIn" can be merged if they are used interchangeably and represent the exact same concept.
    - "focusesOn" and "studies" should **not** be merged unless they are explicitly interchangeable in the context of the graph.

    """

    instructions = [
      %{role: :system, content: system_prompt},
      %{role: :user, content: "Check if duplicates exists in this graph:\n
       #{Jason.encode!(existing_knowledge_graph)}\n"
      }
    ]

    params = %{
      model: "gpt-4o-2024-11-20",
      temperature: 0,
      messages: instructions,
      response_format: %{
        type: "json_schema",
        json_schema: %{
          name: :graph_cleanup,
          schema: %{
            type: "object",
            properties: %{
              nodes: %{
                type: "array",
                items: %{
                  type: "object",
                  properties: %{
                    "node_id_to_replace" => %{type: "string"},
                    "node_id_to_merge_into" => %{type: "string"}
                  },
                  required: ["node_id_to_replace", "node_id_to_merge_into"],
                  additionalProperties: false
                }
              },
              relationships: %{
                type: "array",
                items: %{
                  type: "object",
                  properties: %{
                    "relationship_type_to_replace" => %{type: "string"},
                    "relationship_type_to_merge_into" => %{type: "string"}
                  },
                  required: ["relationship_type_to_replace", "relationship_type_to_merge_into"],
                  additionalProperties: false
                }
              }
            },
            required: ["nodes", "relationships"],
            additionalProperties: false
          },
          strict: true
        }
      }
    }

    generate_cleanup_rules(params)
  end

  defp generate_cleanup_rules(params, retries \\ 3) do
    case Iris.AI.ChatCompletion.complete_chat(params) do
      {:ok, raw_data} ->
        case Jason.decode(raw_data) do
          {:ok, replacements} -> {:ok, replacements}
          {:error, reason} ->
            IO.inspect(reason, label: "JSON Decode Error")
            {:error, :invalid_response}
        end

      {:error, reason} when retries > 0 ->
        IO.puts("Retrying cleanup... (#{retries - 1} attempts left)")
        generate_cleanup_rules(params, retries - 1)

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp apply_replacements(graph, %{"nodes" => node_replacements, "relationships" => rel_replacements}) do
    nodes =
      graph["nodes"]
      |> Enum.map(fn node ->
        replacement =
          Enum.find(node_replacements, fn %{"node_id_to_replace" => from, "node_id_to_merge_into" => _to} ->
            from == node["id"]
          end)

        if replacement do
          %{node | "id" => replacement["node_id_to_merge_into"]}
        else
          node
        end
      end)
      |> Enum.uniq_by(& &1["id"])

    node_replacement_map =
      Enum.into(node_replacements, %{}, fn %{"node_id_to_replace" => from, "node_id_to_merge_into" => to} ->
        {from, to}
      end)

    relationships =
      graph["relationships"]
      |> Enum.map(fn rel ->
        type_replacement =
          Enum.find(rel_replacements, fn %{"relationship_type_to_replace" => from, "relationship_type_to_merge_into" => _to} ->
            from == rel["type"]
          end)

        updated_type =
          if type_replacement do
            type_replacement["relationship_type_to_merge_into"]
          else
            rel["type"]
          end

        updated_source = Map.get(node_replacement_map, rel["source"], rel["source"])
        updated_target = Map.get(node_replacement_map, rel["target"], rel["target"])

        %{rel | "type" => updated_type, "source" => updated_source, "target" => updated_target}
      end)
      |> Enum.uniq_by(fn rel -> {rel["source"], rel["target"], rel["type"]} end)

    %{"nodes" => nodes, "relationships" => relationships}
  end


  defp merge_graph(existing_graph, new_graph) do
    # IO.inspect(existing_graph["nodes"], label: "Existing Graph Nodes")
    # IO.inspect(new_graph[:nodes], label: "New Graph Nodes")
    merged_nodes =
      (existing_graph["nodes"] ++ new_graph[:nodes]      )
      |> Enum.uniq_by(& &1["id"])

    merged_relationships =
      (existing_graph["relationships"] ++ new_graph[:relationships])
      |> Enum.uniq_by(fn rel -> {rel["source"], rel["target"], rel["type"]} end)

    %{
      "nodes" => merged_nodes,
      "relationships" => merged_relationships
    }
  end

  defp ensure_connected_to_root(graph, person_name) do
    # Step 1: Try to find the root node by ID matching the person_name
    root_person =
      graph["nodes"]
      |> Enum.find(fn node -> node["id"] == person_name end)

    # Step 2: If not found, fallback to the first node of type "Person"
    root_person =
      root_person ||
        graph["nodes"]
        |> Enum.find(fn node -> node["type"] == "Person" end)

    if root_person do
      root_id = root_person["id"]

      updated_relationships =
        graph["relationships"]
        |> Enum.map_reduce(graph["relationships"], fn rel, acc ->
          case traverse_to_root(graph, rel["source"], root_id) do
            {:ok, _} ->
              # If the relationship chain is already connected to the root, keep it as is
              {rel, acc}

              {:error, last_node} ->
                # Check if a relationship already exists to avoid duplicates
                new_rel = %{
                  "source" => root_id,
                  "target" => last_node,
                  "type" => "isAssociatedWith"
                }

                unless Enum.any?(acc, fn rel ->
                         rel["source"] == new_rel["source"] and
                           rel["target"] == new_rel["target"] and
                           rel["type"] == new_rel["type"]
                       end) do
                  IO.inspect(last_node, label: "Last Node")
                  {rel, [new_rel | acc]}
                else
                  {rel, acc}
                end

          end
        end)
        |> elem(1)

      # Return the updated graph with new relationships
      %{"nodes" => graph["nodes"], "relationships" => updated_relationships}
    else
      # If no root node is found, return the graph unchanged
      graph
    end
  end

  defp traverse_to_root(graph, node_id, root_id, visited \\ []) do
    # Prevent infinite loops by keeping track of visited nodes
    if node_id in visited do
      {:error, node_id}
    else
      # Check if the current node matches the root ID
      if node_id == root_id do
        {:ok, root_id}
      else
        # Find the next relationship where the current node is the target
        next_rel =
          graph["relationships"]
          |> Enum.find(fn rel -> rel["target"] == node_id end)

        if next_rel do
          # Recursively traverse to the next node in the chain
          traverse_to_root(graph, next_rel["source"], root_id, [node_id | visited])
        else
          # If no further relationship is found, return the last visited node
          {:error, node_id}
        end
      end
    end
  end


  def parse_messages_to_string(persona_name, groups) do
    Enum.map(groups, fn group ->
      updated_messages =
        Enum.map(group.messages, fn message ->
          format_message(persona_name, message)
        end)

      Map.put(group, :messages, updated_messages)
    end)
  end


  def format_message(persona_name, message) do
    case message["actor_role"] do
      "persona" ->
        "#{persona_name}: (assistant): #{message["content"]["value"]}"

      _ ->
        "(user): #{message["content"]["value"]}"
    end
  end
end


 # ## EXAMPLE KNOWLEDGE GRAPH
      # {
      #   "nodes": [
      #     {
      #       "id": "John Doe",
      #       "type": "Person",
      #       "properties": [
      #         {
      #           "key": "age",
      #           "value": "30"
      #         },
      #         {
      #           "key": "occupation",
      #           "value": "Engineer"
      #         },
      #         {
      #           "key": "location",
      #           "value": "New York"
      #         }
      #       ]
      #     },
      #     {
      #       "id": "Software Engineering",
      #       "type": "Concept",
      #       "properties": [
      #         {
      #           "key": "field",
      #           "value": "Technology"
      #         }
      #       ]
      #     },
      #     {
      #       "id": "Jane Doe",
      #       "type": "Person",
      #       "properties": [
      #         {
      #           "key": "age",
      #           "value": "28"
      #         },
      #         {
      #           "key": "occupation",
      #           "value": "Designer"
      #         },
      #         {
      #           "key": "location",
      #           "value": "Los Angeles"
      #         }
      #       ]
      #     }
      #   ],
      #   "relationships": [
      #     {
      #       "source": "John Doe",
      #       "target": "Software Engineering",
      #       "type": "Interested In",
      #       "properties": [
      #         {
      #           "key": "level",
      #           "value": "Expert"
      #         }
      #       ]
      #     },
      #     {
      #       "source": "John Doe",
      #       "target": "Jane Doe",
      #       "type": "Knows",
      #       "properties": [
      #         {
      #           "key": "since",
      #           "value": "2015"
      #         }
      #       ]
      #     }
      #   ]
      # }
