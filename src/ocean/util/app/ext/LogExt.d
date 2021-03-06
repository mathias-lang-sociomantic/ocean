/*******************************************************************************

    Application extension to parse configuration files for the logging system.

    Copyright:
        Copyright (c) 2009-2016 Sociomantic Labs GmbH.
        All rights reserved.

    License:
        Boost Software License Version 1.0. See LICENSE_BOOST.txt for details.
        Alternatively, this file may be distributed under the terms of the Tango
        3-Clause BSD License (see LICENSE_BSD.txt for details).

*******************************************************************************/

module ocean.util.app.ext.LogExt;




import ocean.core.TypeConvert;

import ocean.util.app.model.ExtensibleClassMixin;
import ocean.util.app.Application;
import ocean.util.app.ext.model.IConfigExtExtension;
import ocean.util.app.ext.model.ILogExtExtension;
import ocean.util.app.ext.ConfigExt;

import ocean.util.app.ext.ReopenableFilesExt;

import ocean.util.config.ConfigFiller;
import ocean.util.config.ConfigParser;
import LogUtil = ocean.util.log.Config;
import ConfigFiller = ocean.util.config.ConfigFiller;

import ocean.transition;
import ocean.io.device.File;

import ocean.util.log.Appender;


/*******************************************************************************

    Application extension to parse configuration files for the logging system.

    This extension is an extension itself, providing new hooks via
    ILogExtExtension.

*******************************************************************************/

class LogExt : IConfigExtExtension
{
    /***************************************************************************

        Adds a list of extensions (this.extensions) and methods to handle them.
        See ExtensibleClassMixin documentation for details.

    ***************************************************************************/

    mixin ExtensibleClassMixin!(ILogExtExtension);


    /***************************************************************************

        True if the InsertConsole appender should be used instead of the regular
        one. The InsertConsole appender is needed when using the AppStatus
        module.

    ***************************************************************************/

    public bool use_insert_appender;


    /// If set, will be used by `makeLayout` to map a name to a `Layout`
    private Appender.Layout delegate (cstring name) layout_maker;


    /***************************************************************************

        Constructor.

        Params:
            use_insert_appender = true if the InsertConsole appender should be
                                  used (needed when using the AppStatus module)

    ***************************************************************************/

    this ( bool use_insert_appender )
    {
        this(null, use_insert_appender);
    }


    /***************************************************************************

        Constructor.

        Params:
            make_layout         = A delegate that instantiates an
                                  `Appender.Layout` from a name. If null,
                                  defaults to `ocean.util.Config: newLayout`.
            use_insert_appender = true if the InsertConsole appender should be
                                  used (needed when using the AppStatus module)

    ***************************************************************************/

    public this ( Appender.Layout delegate (cstring name) make_layout = null,
                  bool use_insert_appender = false )
    {
        this.layout_maker = make_layout is null ? &this.makeLayoutDefault
            : make_layout;

        this.use_insert_appender = use_insert_appender;
    }

    /***************************************************************************

        Extension order. This extension uses -1_000 because it should be
        called early, but after the ConfigExt extension.

        Returns:
            the extension order

    ***************************************************************************/

    public override int order ( )
    {
        return -1_000;
    }


    /***************************************************************************

        Parse the configuration file options to set up the loggers.

        Params:
            app = the application instance
            config = configuration instance

    ***************************************************************************/

    public override void processConfig ( IApplication app, ConfigParser config )
    {
        auto conf_ext = (cast(Application)app).getExtension!(ConfigExt);

        foreach (ext; this.extensions)
        {
            ext.preConfigureLoggers(app, config, conf_ext.loose_config_parsing,
                    this.use_insert_appender);
        }

        auto log_config = ConfigFiller.iterate!(LogUtil.Config)("LOG", config);
        auto log_meta_config = ConfigFiller.fill!(LogUtil.MetaConfig)("LOG", config);

        enable_loose_parsing(conf_ext.loose_config_parsing);

        // deprecated: tracks already registered files to prevent double
        // registration by both old and new logger system. Can be removed in
        // ocean v4 together with the old logger.
        File[cstring] registered_files;

        Appender appender ( istring file, LogUtil.Layout layout )
        {
            if (!(file in registered_files))
            {
                auto stream = new File(file, File.WriteAppending);
                if ( auto reopenable_files_ext =
                    (cast(Application)app).getExtension!(ReopenableFilesExt) )
                {
                    reopenable_files_ext.register(stream);
                }
                registered_files[file] = stream;
            }

            return new AppendStream(registered_files[file], true, layout);
        }

        configureOldLoggersLogExtHack(log_config, log_meta_config, &appender,
            this.layout_maker, this.use_insert_appender);

        LogUtil.configureNewLoggers(log_config, log_meta_config, &appender,
            this.layout_maker, this.use_insert_appender);

        foreach (ext; this.extensions)
        {
            ext.postConfigureLoggers(app, config, conf_ext.loose_config_parsing,
                    this.use_insert_appender);
        }
    }


    /***************************************************************************

        Unused IConfigExtExtension methods.

        We just need to provide an "empty" implementation to satisfy the
        interface.

        Params:
            app = the application instance
            config = configuration instance

    ***************************************************************************/

    public override void preParseConfig ( IApplication app, ConfigParser config )
    {
        // Unused
    }


    /***************************************************************************

        Function to filter the list of configuration files to parse.
        Only present to satisfy the interface

        Params:
            app = the application instance
            config = configuration instance
            files = current list of configuration files to parse

        Returns:
            new list of configuration files to parse

    ***************************************************************************/

    public override istring[] filterConfigFiles ( IApplication app,
                                         ConfigParser config,
                                         istring[] files )
    {
        // Unused
        return files;
    }


    /***************************************************************************

        Default for layout_maker. DMD complains because `LogUtil.newLayout`
        is a function, not a delegate.

        Params:
            name = name of the Layout to instantiate.

        Throws:
            `Exception` if it cannot match the name

        Returns:
            A new Layout instance matching name

    ***************************************************************************/

    private Appender.Layout makeLayoutDefault ( cstring name )
    {
        return LogUtil.newLayout(name);
    }
}


/// Hack to allow to call a deprecated function without deprecations
/// TODO: Remove for v4.0.0 release with other deprecated things
private extern extern(C) void configureOldLoggersLogExtHack (
    ClassIterator!(LogUtil.Config, ConfigParser) config,
    LogUtil.MetaConfig m_config,
    AppenderExternD file_appender, MakeLayoutExternD makeLayout,
    bool use_insert_appender = false);
/// Hack because DMD1 applies extern(C) to the delegate type as well...
private alias extern(D) Appender delegate (istring, Appender.Layout)
    AppenderExternD;
/// Ditto
private alias extern(D) Appender.Layout delegate (cstring)
    MakeLayoutExternD;
