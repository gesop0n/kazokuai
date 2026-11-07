package server

import (
	"reflect"
	"strings"
)

// schemaOf は、Go の構造体から JSON Schema を作る。
// Gemini の ResponseJsonSchema に渡し、まとめの形を構造体と揃える。
func schemaOf(value any) map[string]any {
	return schemaType(reflect.TypeOf(value))
}

func schemaType(t reflect.Type) map[string]any {
	for t.Kind() == reflect.Pointer {
		t = t.Elem()
	}
	switch t.Kind() {
	case reflect.Struct:
		properties := map[string]any{}
		var required []string
		for i := 0; i < t.NumField(); i++ {
			field := t.Field(i)
			if field.PkgPath != "" {
				continue
			}
			name, ok := jsonFieldName(field)
			if !ok {
				continue
			}
			property := schemaType(field.Type)
			applySchemaTag(field, property)
			properties[name] = property
			required = append(required, name)
		}
		return map[string]any{
			"type":                 "object",
			"properties":           properties,
			"required":             required,
			"additionalProperties": false,
		}
	case reflect.Slice:
		return map[string]any{
			"type":  "array",
			"items": schemaType(t.Elem()),
		}
	case reflect.String:
		return map[string]any{"type": "string"}
	case reflect.Bool:
		return map[string]any{"type": "boolean"}
	case reflect.Int, reflect.Int32, reflect.Int64:
		return map[string]any{"type": "integer"}
	default:
		panic("まとめの schema にできない型: " + t.String())
	}
}

func jsonFieldName(field reflect.StructField) (string, bool) {
	tag := field.Tag.Get("json")
	name, _, _ := strings.Cut(tag, ",")
	if name == "" || name == "-" {
		return "", false
	}
	return name, true
}

func applySchemaTag(field reflect.StructField, property map[string]any) {
	var enum []any
	for _, part := range strings.Split(field.Tag.Get("schema"), ",") {
		value, ok := strings.CutPrefix(part, "enum=")
		if ok {
			enum = append(enum, value)
		}
	}
	if len(enum) > 0 {
		property["enum"] = enum
	}
}
