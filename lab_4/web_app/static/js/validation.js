/*
 * Клієнтська валідація форм (рівень 3).
 * Правила задаються атрибутами data-* у полях форми:
 *   required, data-pattern="regex", data-pattern-msg="...", data-min / data-max (числа),
 *   data-match="id іншого поля" (підтвердження пароля), data-after="id поля" (рік смерті ≥ року народження),
 *   data-min-selected="1" (для select multiple).
 * Сервер виконує ту саму перевірку повторно — клієнтська лише пришвидшує зворотний зв'язок.
 */
(function () {
    "use strict";

    function showError(input, message) {
        const field = input.closest(".field");
        if (!field) return;
        let box = field.querySelector(".error.js");
        if (message) {
            field.classList.add("invalid");
            if (!box) {
                box = document.createElement("span");
                box.className = "error js";
                field.appendChild(box);
            }
            box.textContent = message;
        } else {
            field.classList.remove("invalid");
            if (box) box.remove();
        }
    }

    function validateInput(input) {
        const value = (input.value || "").trim();
        const label = input.dataset.label || input.name;

        if (input.multiple) {
            const need = parseInt(input.dataset.minSelected || "0", 10);
            const selected = Array.from(input.options).filter(o => o.selected).length;
            return selected < need ? `Оберіть щонайменше ${need}` : "";
        }
        if (input.required && !value) return `Поле «${label}» обов'язкове`;
        if (!value) return "";

        if (input.dataset.pattern && !new RegExp("^(?:" + input.dataset.pattern + ")$").test(value)) {
            return input.dataset.patternMsg || "Невірний формат";
        }
        if (input.dataset.min !== undefined || input.dataset.max !== undefined) {
            const num = Number(value.replace(",", "."));
            if (Number.isNaN(num)) return `«${label}» має бути числом`;
            if (input.dataset.min !== undefined && num < Number(input.dataset.min)) return `Мінімум: ${input.dataset.min}`;
            if (input.dataset.max !== undefined && num > Number(input.dataset.max)) return `Максимум: ${input.dataset.max}`;
        }
        if (input.dataset.match) {
            const other = document.getElementById(input.dataset.match);
            if (other && other.value !== input.value) return "Паролі не збігаються";
        }
        if (input.dataset.after) {
            const other = document.getElementById(input.dataset.after);
            if (other && other.value && Number(value) < Number(other.value)) return "Не може бути раніше року народження";
        }
        if (input.type === "date" && input.dataset.past !== undefined && new Date(value) > new Date()) {
            return "Дата не може бути в майбутньому";
        }
        return "";
    }

    function validateForm(form) {
        let firstInvalid = null;
        form.querySelectorAll("input, select, textarea").forEach(input => {
            if (input.type === "hidden" || input.type === "submit") return;
            const message = validateInput(input);
            showError(input, message);
            if (message && !firstInvalid) firstInvalid = input;
        });
        if (firstInvalid) firstInvalid.focus();
        return !firstInvalid;
    }

    document.addEventListener("DOMContentLoaded", () => {
        document.querySelectorAll("form[data-validate]").forEach(form => {
            form.setAttribute("novalidate", "novalidate");      // вимикаємо стандартні підказки браузера
            form.addEventListener("submit", event => {
                if (!validateForm(form)) event.preventDefault();
            });
            // перевірка «на льоту» при виході з поля
            form.querySelectorAll("input, select, textarea").forEach(input => {
                input.addEventListener("blur", () => showError(input, validateInput(input)));
                input.addEventListener("input", () => {
                    if (input.closest(".field")?.classList.contains("invalid")) showError(input, validateInput(input));
                });
            });
        });

        // індикатор надійності пароля
        const pwd = document.getElementById("password");
        const meter = document.getElementById("password-strength");
        if (pwd && meter) {
            pwd.addEventListener("input", () => {
                const v = pwd.value;
                let score = 0;
                if (v.length >= 8) score++;
                if (/\d/.test(v)) score++;
                if (/[A-ZА-ЯІЇЄ]/.test(v) && /[a-zа-яіїє]/.test(v)) score++;
                if (/[^A-Za-z0-9А-Яа-яІіЇїЄє]/.test(v)) score++;
                meter.textContent = ["дуже слабкий", "слабкий", "середній", "надійний", "дуже надійний"][score];
                meter.style.color = ["#b3261e", "#b3261e", "#a86500", "#2e7d4f", "#2e7d4f"][score];
            });
        }

        // підтвердження небезпечних дій
        document.querySelectorAll("form[data-confirm]").forEach(form => {
            form.addEventListener("submit", event => {
                if (!window.confirm(form.dataset.confirm)) event.preventDefault();
            });
        });
    });
})();
