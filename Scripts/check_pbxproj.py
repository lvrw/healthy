#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""OpenStep ASCII 版 pbxproj 的独立解析器，用于把"project is damaged"定位到具体行。

Xcode 报这个错时不给行号（它其实是被迫回落到 JSON 解析后失败的），
所以自己按 {}/()/"" 的规则走一遍，第一个不合法的地方就是真正的病灶。
"""

import re
import sys

BARE_TOKEN = re.compile(r"[A-Za-z0-9_.$/:\-+@~*<>=!&|,^?\[\]#]+$")
NUMBER = re.compile(r"^[+-]?[0-9]+(\.[0-9]+)?$")


class Failure(Exception):
    def __init__(self, line, column, message):
        super(Failure, self).__init__("第 {0} 行 列 {1}: {2}".format(line, column, message))
        self.line = line
        self.column = column


def tokenize(text):
    tokens = []
    i = 0
    line = 1
    length = len(text)
    while i < length:
        ch = text[i]
        if ch == "\n":
            line += 1
            i += 1
            continue
        if ch in " \t\r":
            i += 1
            continue
        if text.startswith("//", i):
            while i < length and text[i] != "\n":
                i += 1
            continue
        if text.startswith("/*", i):
            end = text.find("*/", i + 2)
            if end < 0:
                raise Failure(line, 1, "块注释没有闭合")
            line += text.count("\n", i, end)
            i = end + 2
            continue
        if ch == '"':
            j = i + 1
            buf = []
            while j < length and text[j] != '"':
                if text[j] == "\\":
                    buf.append(text[j:j + 2])
                    j += 2
                    continue
                buf.append(text[j])
                j += 1
            if j >= length:
                raise Failure(line, 1, "字符串没有闭合")
            tokens.append(("string", "".join(buf), line))
            i = j + 1
            continue
        if ch in "{}()=;,":
            tokens.append(("punct", ch, line))
            i += 1
            continue
        j = i
        while j < length and text[j] not in " \t\r\n{}()=;,\"":
            j += 1
        raw = text[i:j]
        tokens.append(("bare", raw, line))
        i = j
    return tokens


class Parser(object):
    def __init__(self, tokens):
        self.tokens = tokens
        self.pos = 0

    def peek(self):
        return self.tokens[self.pos] if self.pos < len(self.tokens) else None

    def next(self):
        token = self.peek()
        if token is None:
            raise Failure(self.tokens[-1][2] if self.tokens else 1, 1, "内容意外结束")
        self.pos += 1
        return token

    def expect(self, value):
        token = self.next()
        if token[0] != "punct" or token[1] != value:
            raise Failure(token[2], 1, "期望 {0}，实际是 {1!r}".format(value, token[1]))

    def parse_value(self):
        token = self.next()
        kind, value, line = token
        if kind == "string":
            return
        if kind == "bare":
            if value.startswith("$"):
                return
            if BARE_TOKEN.match(value):
                return
            raise Failure(line, 1, "裸值含非法字符: {0!r}（应当加引号）".format(value))
        if value == "{":
            while True:
                token = self.peek()
                if token is None:
                    raise Failure(line, 1, "字典没有闭合")
                if token[0] == "punct" and token[1] == "}":
                    self.next()
                    return
                self.next()
                self.expect("=")
                self.parse_value()
                self.expect(";")
        if value == "(":
            while True:
                token = self.peek()
                if token is None:
                    raise Failure(line, 1, "数组没有闭合")
                if token[0] == "punct" and token[1] == ")":
                    self.next()
                    return
                self.parse_value()
                token = self.peek()
                if token and token[0] == "punct" and token[1] == ",":
                    self.next()
                else:
                    self.expect(")")
                    return
        raise Failure(line, 1, "意外的值起始符 {0!r}".format(value))

    def parse(self):
        self.expect("{")
        while True:
            token = self.peek()
            if token is None:
                raise Failure(1, 1, "根字典没有闭合")
            if token[0] == "punct" and token[1] == "}":
                self.next()
                return
            self.next()
            self.expect("=")
            self.parse_value()
            self.expect(";")


def main():
    path = sys.argv[1]
    with open(path, "r", encoding="utf-8") as handle:
        text = handle.read()
    try:
        Parser(tokenize(text)).parse()
    except Failure as failure:
        print("解析失败 -> {0}".format(failure))
        lines = text.split("\n")
        for offset in range(max(0, failure.line - 3), min(len(lines), failure.line + 2)):
            marker = ">>" if offset + 1 == failure.line else "  "
            print("{0} {1:5d} | {2}".format(marker, offset + 1, lines[offset]))
        return 1
    print("OpenStep 解析通过：{0}".format(path))
    return 0


if __name__ == "__main__":
    sys.exit(main())
