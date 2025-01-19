#!/bin/bash

# Настройки
BASE_URL="http://localhost:8080/api/v0/prices"
ARCHIVE_TYPE="zip"
ARCHIVE_PATH="./sample_data.zip"

# Проверка наличия curl
if ! command -v curl &> /dev/null; then
    echo "curl не установлен. Установите его перед запуском скрипта."
    exit 1
fi

# Проверка наличия тестового архива
if [[ ! -f "$ARCHIVE_PATH" ]]; then
    echo "Файл тестового архива $ARCHIVE_PATH не найден."
    exit 1
fi


# POST запрос
echo "Отправляем POST запрос с архивом $ARCHIVE_PATH..."
POST_RESPONSE=$(curl -s -X POST "$BASE_URL" \
    -H "Content-Type: application/zip" \
    --data-binary @"$ARCHIVE_PATH")

if [[ $? -ne 0 ]]; then
    echo "Ошибка при выполнении POST запроса."
    exit 1
fi

echo "Ответ на POST запрос:"
echo "$POST_RESPONSE"

# Проверка ответа POST
TOTAL_ITEMS=$(echo "$POST_RESPONSE" | jq -r '.total_items')
if [[ -z "$TOTAL_ITEMS" || "$TOTAL_ITEMS" == "null" ]]; then
    echo "POST запрос вернул некорректный ответ."
    exit 1
fi

echo "POST запрос успешен. Добавлено $TOTAL_ITEMS элементов."


# POST запрос
echo "Отправляем POST запрос с архивом $ARCHIVE_PATH..."
POST_RESPONSE=$(curl -s -X POST "$BASE_URL?type=$ARCHIVE_TYPE" \
    -H "Content-Type: application/zip" \
    --data-binary @"$ARCHIVE_PATH")

if [[ $? -ne 0 ]]; then
    echo "Ошибка при выполнении POST запроса."
    exit 1
fi

echo "Ответ на POST запрос:"
echo "$POST_RESPONSE"

# Проверка ответа POST
TOTAL_ITEMS=$(echo "$POST_RESPONSE" | jq -r '.total_items')
if [[ -z "$TOTAL_ITEMS" || "$TOTAL_ITEMS" == "null" ]]; then
    echo "POST запрос вернул некорректный ответ."
    exit 1
fi

echo "POST запрос успешен. Добавлено $TOTAL_ITEMS элементов."

# GET запрос
echo "Отправляем GET запрос для получения архива данных..."
GET_RESPONSE=$(curl -s -X GET "$BASE_URL" --output output.zip)

if [[ $? -ne 0 ]]; then
    echo "Ошибка при выполнении GET запроса."
    exit 1
fi

if [[ -f "output.zip" ]]; then
    echo "GET запрос успешен. Получен файл output.zip."
    echo "Содержимое архива:"
    unzip -l output.zip
    rm output.zip
else
    echo "GET запрос не вернул архив."
    exit 1
fi

echo "Тесты успешно выполнены."
