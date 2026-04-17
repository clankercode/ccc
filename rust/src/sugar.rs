use crate::invoke::Error;
use crate::invoke::Request;
use crate::parser::{parse_args, resolve_command_warnings, CccConfig};

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct ParsedRequest {
    pub request: Request,
    pub warnings: Vec<String>,
}

pub fn parse_tokens<I, S>(tokens: I) -> Result<ParsedRequest, Error>
where
    I: IntoIterator<Item = S>,
    S: Into<String>,
{
    parse_tokens_with_config(tokens, &CccConfig::default())
}

pub fn parse_tokens_with_config<I, S>(tokens: I, config: &CccConfig) -> Result<ParsedRequest, Error>
where
    I: IntoIterator<Item = S>,
    S: Into<String>,
{
    let argv: Vec<String> = tokens.into_iter().map(Into::into).collect();
    let parsed = parse_args(&argv);
    let request = Request::from_parsed_args(&parsed).map_err(Error::InvalidRequest)?;
    let warnings =
        resolve_command_warnings(&parsed, Some(config)).map_err(Error::InvalidRequest)?;

    Ok(ParsedRequest { request, warnings })
}
