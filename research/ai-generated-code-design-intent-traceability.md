# AI生成コードの設計意図トレーサビリティ調査

## 結論

AI支援そのものを一律に禁止または推奨できる証拠はない。一方、生成量の増加、重複、レビュー負荷、技能形成への影響を示す研究があり、数か月後の保守性をモデルの自己説明だけに委ねるのは危険である。本ハーネスでは、変更を小さく保ち、人間がコードを理解してレビューし、重要な設計意図を短いChange Intent Recordで要件・コード・テスト・ADRへ結び付ける。

完全な会話transcriptやAIの内部思考は、長く、検証しにくく、秘密情報を含み得るため正本にしない。保存するのは採用した判断、理由、制約、却下した主要代替案、検証可能な参照である。

独立Reviewerに加え、その変更に責任を持つ人間がコード、テスト、設計意図の一致をレビューする。AI/LLM Reviewerの説明またはPASSだけで完了としない。

## 観測されたリスク

- 2026年の技術的負債に関する研究は、AI生成コード利用と保守上の負債の関係を分析している。ただし査読前のpreprintであり、対象、測定方法、利用環境を越えた因果関係は確立していない。
- 2026年のコード重複に関する研究は、生成AI利用と冗長・重複コードの関係を報告し、MSR 2026に採録されている。モデル、言語、リポジトリ特性への一般化には注意が必要である。
- DORAの調査は、生成AIの利用が文書品質などの改善と関連する一方、デリバリ安定性などに複雑な関連を持つと報告する。観察研究の関連であり、個々の変更に対する因果効果ではない。
- METRの無作為化比較研究では、成熟したOSSリポジトリに詳しい経験豊富な開発者が当時のAIツールを使った条件で、作業時間短縮が確認されず、自己認識ともずれがあった。特定参加者、特定タスク、2025年前半のツールという限定がある。
- Anthropicの無作為化研究は、学習目的のコーディング課題でAI支援が技能獲得を弱め得ることを示す。ただし短期の教育課題であり、熟練者の実務保守性へ直接一般化できない。
- Microsoft Researchの知識労働者調査は、生成AIへの信頼と自己申告された批判的思考の間の関係を報告する。自己申告調査であり、コード品質の客観測定でも因果推定でもない。

## 限定条件と反証

- AI支援が常に保守性を悪化させるわけではない。2025年の研究には、限定された課題・評価条件で品質または保守性の改善を報告するpreprintもある。
- 生産性、正確性、学習、長期保守性は別の評価軸である。短期タスクの成功を、数か月後の理解容易性の証拠として扱わない。
- 研究ごとにモデル、ツール、参加者、言語、リポジトリ成熟度、評価指標が異なる。結果は方向性を検討する材料であり、単一の数値を全プロジェクトへ適用しない。
- 本調査が支持するのは「AI生成コードは悪い」という結論ではなく、通常の小さい変更、テスト、独立レビュー、文書化を省略しないという運用である。

## 実務上の対策

1. 変更を小さく自己完結させ、レビュー可能な単位を越えたら上位ハーネスへ昇格する。
2. テストを先に書き、生成コードの説明ではなく実行結果と終了コードで挙動を検証する。
3. 独立Reviewerが正確性、複雑性、重複、セキュリティ、テスト品質を確認し、さらに変更へ責任を持つ人間がコードと設計意図を理解して承認する。
4. 非自明な変更だけに短いChange Intent Recordを作り、目的、理由、制約、対象外、主要代替案を要件・コード・テスト・ADRへリンクする。
5. レビューコメントは理解して解消し、単に応答済みにしない。後から読めない抽象化や将来要件への先回りを拒否する。
6. 記録と実装の不一致をレビューし、古い文書を残さない。長い会話ログを保守文書の代用にしない。

## 一次資料

- [Technical-debt study (arXiv:2603.28592)](https://arxiv.org/abs/2603.28592) — AI生成コードと技術的負債を扱う2026年のpreprint。査読状況と測定範囲を限定して解釈する。
- [Code-redundancy study (arXiv:2601.21276)](https://arxiv.org/abs/2601.21276) — AI支援とコードの冗長性・重複を扱い、MSR 2026に採録された研究。
- [DORA Impact of Generative AI in Software Development](https://dora.dev/ai/gen-ai-report/dora-impact-of-generative-ai-in-software-development.pdf) — 開発成果との関連を扱う調査報告。観察的な関連を因果効果とみなさない。
- [METR: Early-2025 AI experienced OSS developer study](https://metr.org/blog/2025-07-10-early-2025-ai-experienced-os-dev-study/) — 経験豊富なOSS開発者を対象にした無作為化比較研究。対象とツール時点に限定がある。
- [Anthropic: AI assistance and coding skills](https://www.anthropic.com/research/AI-assistance-coding-skills) — AI支援と技能形成の無作為化研究。短期の学習課題という限定がある。
- [Counterevidence study (arXiv:2507.00788)](https://arxiv.org/abs/2507.00788) — AI支援の肯定的効果を含む2025年のpreprint。実験条件外へ一般化しない。
- [Maintainability-related study (arXiv:2508.00700)](https://arxiv.org/abs/2508.00700) — AI生成コードの品質・保守性を扱う2025年のpreprint。評価指標と対象範囲に依存する。
- [Microsoft Research: The Impact of Generative AI on Critical Thinking](https://www.microsoft.com/en-us/research/publication/the-impact-of-generative-ai-on-critical-thinking-self-reported-reductions-in-cognitive-effort-and-confidence-effects-from-a-survey-of-knowledge-workers/) — 知識労働者の自己申告調査。客観的コード品質や因果関係の測定ではない。
- [Google Engineering Practices: Small CLs](https://google.github.io/eng-practices/review/developer/small-cls.html) — 小さく自己完結した変更を推奨するレビュー実務。
- [GitHub Copilot coding agent responsible use](https://docs.github.com/en/copilot/responsible-use/agents) — 生成結果を利用者がレビューし、検証する責任を明記する公式文書。
- [Google Engineering Practices: Handling reviewer comments](https://google.github.io/eng-practices/review/developer/handling-comments.html) — コメントの理解、合意、修正を扱う実務指針。
- [Google Engineering Practices: What to look for in a code review](https://google.github.io/eng-practices/review/reviewer/looking-for.html) — 設計、複雑性、テスト、コメント等を確認するレビュー指針。
